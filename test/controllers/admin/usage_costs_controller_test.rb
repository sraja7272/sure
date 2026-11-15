require "test_helper"

class Admin::UsageCostsControllerTest < ActionDispatch::IntegrationTest
  include TableTestHelper

  RATE_SETTINGS = PlaidItemUsage::RATE_SETTINGS.values.map(&:to_s).freeze

  setup do
    @super_admin = users(:sure_support_staff)
    @member = users(:family_member)

    LlmUsage.create!(
      family: @member.family, user: @member, provider: "openai", model: "gpt-4.1", operation: "chat",
      prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, estimated_cost: "0.4321",
      created_at: Time.zone.local(2026, 10, 15, 12)
    )
    LlmUsage.create!(
      family: @member.family, user: nil, provider: "custom", model: "local-llm", operation: "chat",
      prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, estimated_cost: nil,
      created_at: Time.zone.local(2026, 10, 15, 12)
    )
  end

  teardown do
    Setting.where(var: RATE_SETTINGS).delete_all
    Setting.clear_cache
  end

  test "super admin sees the month's report grouped by family" do
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    assert_response :success
    assert_includes response.body, @member.display_name
    assert_select "section h3", text: @member.family.name
    assert_includes response.body, I18n.t("admin.usage_costs.show.unassigned")
    assert_includes response.body, I18n.t("usage_costs.requests.unpriced", count: 1)
    assert_select "a[href='#{admin_usage_costs_path(month: "2026-09")}']"
    assert_includes response.body, I18n.t("admin.usage_costs.show.estimates_body")
    assert_not_includes response.body, "Attribution to people"
    assert_select "table th", text: I18n.t("admin.usage_costs.show.ai_requests")
    assert_select ".translation_missing", count: 0
  end

  test "a sub-cent total is not rounded to zero" do
    LlmUsage.create!(
      family: @member.family, user: @member, provider: "openai", model: "gpt-4.1", operation: "chat",
      prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, estimated_cost: "0.004",
      created_at: Time.zone.local(2026, 9, 15, 12)
    )
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-09")

    assert_equal "$0.0040", summary_card_value(I18n.t("usage_costs.summary.total"))
    assert_equal "$0.0040", last_cell_of_row(@member.display_name)
    assert_equal "$0.0040", last_cell_of_row(I18n.t("admin.usage_costs.show.subtotal"))
  end

  test "privacy mode blurs every cost in the family tables but not the counts" do
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    cost_headers = %w[ai_cost plaid_cost total].map { |key| I18n.t("admin.usage_costs.show.#{key}") }
    count_headers = %w[ai_requests plaid_items].map { |key| I18n.t("admin.usage_costs.show.#{key}") }
    # Person rows, the Unassigned row and the Subtotal row alike.
    row_headers = css_select("tbody tr th").map { |th| th.text.strip }
    assert row_headers.any? { |text| text.include?(@member.display_name) }
    assert_includes row_headers, I18n.t("admin.usage_costs.show.unassigned")
    assert_includes row_headers, I18n.t("admin.usage_costs.show.subtotal")
    cost_headers.each do |header|
      assert_equal css_select("tbody tr").size, column_cells(header).size
      assert column_cells(header).all? { |cell| cell.classes.include?("privacy-sensitive") }, "#{header} cells are not privacy-sensitive"
    end
    count_headers.each do |header|
      assert column_cells(header).none? { |cell| cell.classes.include?("privacy-sensitive") }, "#{header} cells are privacy-sensitive"
    end
  end

  test "choosing a month loads it without a submit button" do
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    assert_select "form[method='get'][data-controller='auto-submit-form']" do
      assert_select "label.sr-only[for='month']", text: I18n.t("usage_costs.month_nav.month")
      assert_select "input[type='month'][name='month'][value='2026-10'][data-auto-submit-form-target='auto']"
      assert_select "button[type='submit'], input[type='submit']", count: 0
    end
  end

  test "super admin downloads the month as CSV" do
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10", format: :csv)

    assert_response :success
    assert_equal "text/csv", response.media_type
    assert_includes response.headers["Content-Disposition"], "usage-costs-2026-10.csv"
    rows = CSV.parse(response.body)
    assert_equal "Period", rows.first.first
    assert_includes rows.map { |row| row[2] }, @member.display_name
  end

  test "family admins and members are redirected" do
    %i[family_admin family_member].each do |fixture|
      sign_in users(fixture)

      get admin_usage_costs_path

      assert_redirected_to root_path
      assert_equal I18n.t("admin.unauthorized"), flash[:alert]
    end
  end

  test "only super admins get the report in the settings nav" do
    sign_in @super_admin
    get settings_preferences_path
    assert_select "nav a[href='#{admin_usage_costs_path}']", count: 2

    sign_in users(:family_admin)
    get settings_preferences_path
    assert_select "nav a[href='#{admin_usage_costs_path}']", count: 0
  end

  test "rate inputs show the dollar sign and keep sub-cent rates" do
    Setting.plaid_rate_investments_holdings = BigDecimal("0.125")
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    assert_response :success
    PlaidItemUsage::RATE_SETTINGS.each_key do |key|
      assert_select "span[data-money-field-target='symbol'] + input[name='plaid_rates[#{key}]']"
    end
    assert_select "span[data-money-field-target='symbol']", text: Money::Currency.new("USD").symbol, count: 5
    assert_select "input[name='plaid_rates[transactions]'][value='0.00']"
    assert_select "input[name='plaid_rates[investments_holdings]'][value='0.125']"
    assert_select "select[name^='plaid_rates']", count: 0
    assert_select "[data-action*='money-field#insertOperator']", count: 0
  end

  test "a saved rate renders at least two decimals and the fields ask for two on blur" do
    Setting.plaid_rate_transactions = BigDecimal("0.2")
    Setting.plaid_rate_liabilities = BigDecimal("3")
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    assert_select "input[name='plaid_rates[transactions]'][value='0.20']"
    assert_select "input[name='plaid_rates[liabilities]'][value='3.00']"
    # Read by money_field_controller, which pads an unrounded rate typed as
    # ".2" to "0.20" when the field loses focus.
    assert_select "[data-controller='money-field'][data-money-field-min-precision-value='2']", count: PlaidItemUsage::RATE_SETTINGS.size
  end

  test "rates form groups the rates by product" do
    sign_in @super_admin

    get admin_usage_costs_path(month: "2026-10")

    groups = css_select("form fieldset").map do |fieldset|
      [ fieldset.at_css("legend").text.strip, fieldset.css("input[name^='plaid_rates']").map { |input| input["name"] } ]
    end
    assert_equal [
      [ "Transactions", %w[plaid_rates[transactions] plaid_rates[transactions_refresh]] ],
      [ "Investments", %w[plaid_rates[investments_holdings] plaid_rates[investments_transactions]] ],
      [ "Liabilities", %w[plaid_rates[liabilities]] ]
    ], groups
    assert_includes response.body, I18n.t("admin.usage_costs.show.rates_unused_products")
  end

  test "update saves the Plaid rates" do
    sign_in @super_admin

    patch admin_usage_costs_path, params: {
      month: "2026-10",
      plaid_rates: {
        transactions: "0.30", transactions_refresh: "0.12",
        investments_holdings: "0.18", investments_transactions: "0.07", liabilities: "0.2"
      }
    }

    assert_redirected_to admin_usage_costs_path(month: "2026-10")
    assert_equal I18n.t("admin.usage_costs.update.success"), flash[:notice]
    assert_equal BigDecimal("0.30"), Setting.plaid_rate_transactions.to_d
    assert_equal BigDecimal("0.18"), Setting.plaid_rate_investments_holdings.to_d
    assert_equal BigDecimal("0.07"), Setting.plaid_rate_investments_transactions.to_d
    assert_equal BigDecimal("0.2"), Setting.plaid_rate_liabilities.to_d
    assert_equal BigDecimal("0.12"), Setting.plaid_rate_transactions_refresh.to_d
  end

  test "update rejects a negative or non-numeric rate and saves nothing" do
    sign_in @super_admin

    [ "-1", "abc", "" ].each do |bad|
      patch admin_usage_costs_path, params: {
        month: "2026-10",
        plaid_rates: {
          transactions: "0.30", transactions_refresh: "0.12",
          investments_holdings: bad, investments_transactions: "0.07", liabilities: "0.2"
        }
      }

      assert_redirected_to admin_usage_costs_path(month: "2026-10")
      assert_equal I18n.t("admin.usage_costs.update.invalid"), flash[:alert]
      assert_equal 0, Setting.plaid_rate_transactions.to_d
      assert_equal 0, Setting.plaid_rate_investments_holdings.to_d
    end
  end

  test "non-super-admins cannot update the rates" do
    sign_in users(:family_admin)

    patch admin_usage_costs_path, params: { plaid_rates: { transactions: "9.99" } }

    assert_redirected_to root_path
    assert_equal 0, Setting.plaid_rate_transactions.to_d
  end

  private
    def summary_card_value(title)
      css_select("h4").find { |heading| heading.text.strip == title }.next_element.text.strip
    end

    # The row's header cell holds the person's name (or "Subtotal"); the last
    # cell is the Total column.
    def last_cell_of_row(header_text)
      row = css_select("tbody tr").find { |tr| tr.at_css("th")&.text&.include?(header_text) }
      row.css("td").last.text.strip
    end
end
