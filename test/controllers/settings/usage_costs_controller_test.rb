require "test_helper"

class Settings::UsageCostsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @member = users(:family_member)
    @admin = users(:family_admin)
    @outsider = users(:josh)
    @month = Time.zone.local(2026, 10, 15, 12)

    ai_usage(@member, cost: "0.4321", operation: "auto_categorize")
    ai_usage(@admin, cost: "7.7777", operation: "chat")
    ai_usage(@outsider, cost: "8.8888", operation: "chat")
    ai_usage(nil, cost: "9.9999", operation: "chat", family: @member.family)

    plaid_usage(@member, "Member Credit Union")
    plaid_usage(@admin, "Admin Savings Bank")
    plaid_usage(@outsider, "Outsider Trust")
  end

  test "a member sees their own figures for the month" do
    sign_in @member

    get settings_usage_costs_path(month: "2026-10")

    assert_response :success
    assert_includes response.body, "$0.4321"
    assert_includes response.body, I18n.t("usage_costs.operations.auto_categorize")
    assert_includes response.body, "Member Credit Union"
    assert_select "section h3", text: I18n.t("settings.usage_costs.show.ai_title")
    assert_select "section h3", text: I18n.t("settings.usage_costs.show.plaid_title")
    assert_select "table th", text: I18n.t("settings.usage_costs.show.institution")
    assert_select ".translation_missing", count: 0
  end

  test "a sub-cent total is not rounded to zero" do
    LlmUsage.create!(
      family: @member.family, user: @member, provider: "openai", model: "gpt-4.1", operation: "chat",
      prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, estimated_cost: "0.004",
      created_at: Time.zone.local(2026, 9, 15, 12)
    )
    sign_in @member

    get settings_usage_costs_path(month: "2026-09")

    total = css_select("h4").find { |heading| heading.text.strip == I18n.t("usage_costs.summary.total") }
    assert_equal "$0.0040", total.next_element.text.strip
  end

  test "privacy mode blurs every cost but not the counts" do
    sign_in @member

    get settings_usage_costs_path(month: "2026-10")

    summary_titles = %w[total ai_cost plaid_cost].map { |key| I18n.t("usage_costs.summary.#{key}") }
    summary_titles.each do |title|
      value = css_select("h4").find { |heading| heading.text.strip == title }.next_element
      assert_includes value.classes, "privacy-sensitive"
    end

    cost_cells = column_cells(I18n.t("settings.usage_costs.show.cost"))
    # One AI feature row and one Plaid connection row.
    assert_equal 2, cost_cells.size
    assert cost_cells.all? { |cell| cell.classes.include?("privacy-sensitive") }, "cost cells are not privacy-sensitive"

    %w[requests refreshes].each do |key|
      cells = column_cells(I18n.t("settings.usage_costs.show.#{key}"))
      assert cells.any?
      assert cells.none? { |cell| cell.classes.include?("privacy-sensitive") }, "#{key} cells are privacy-sensitive"
    end
  end

  test "choosing a month loads it without a submit button" do
    sign_in @member

    get settings_usage_costs_path(month: "2026-10")

    assert_select "form[method='get'][data-controller='auto-submit-form']" do
      assert_select "label.sr-only[for='month']", text: I18n.t("usage_costs.month_nav.month")
      assert_select "input[type='month'][name='month'][value='2026-10'][data-auto-submit-form-target='auto']"
      assert_select "button[type='submit'], input[type='submit']", count: 0
    end
  end

  test "the current month is the UTC month, not the family's" do
    @member.family.update!(timezone: "America/Los_Angeles")
    sign_in @member

    # 8pm on 31 October in Los Angeles is already November in UTC.
    travel_to Time.utc(2026, 11, 1, 3) do
      get settings_usage_costs_path
    end

    assert_response :success
    assert_includes response.body, I18n.l(Date.new(2026, 11, 1), format: :month_year)
    assert_select "input[type='month'][name='month'][value='2026-11'][max='2026-11']"
  end

  test "never shows another user's usage" do
    sign_in @member

    get settings_usage_costs_path(month: "2026-10")

    assert_no_other_users_figures
  end

  test "user and family params cannot select someone else" do
    sign_in @member

    get settings_usage_costs_path(month: "2026-10", user_id: @admin.id, family_id: @outsider.family_id)

    assert_response :success
    assert_includes response.body, "Member Credit Union"
    assert_no_other_users_figures
  end

  test "guests can see their own page" do
    sign_in users(:intro_user)

    get settings_usage_costs_path(month: "2026-10")

    assert_response :success
    assert_includes response.body, I18n.t("settings.usage_costs.show.no_usage")
  end

  test "every role gets the page in the settings nav" do
    %i[family_admin family_member intro_user].each do |fixture|
      sign_in users(fixture)
      get settings_preferences_path

      assert_select "nav a[href='#{settings_usage_costs_path}']", count: 2
    end
  end

  private
    # The body cells under a column heading, across every table on the page.
    def column_cells(header)
      css_select("table").flat_map do |table|
        index = table.css("thead th").map { |th| th.text.strip }.index(header)
        next [] unless index

        table.css("tbody tr").map { |tr| tr.element_children[index] }
      end
    end

    def assert_no_other_users_figures
      %w[7.7777 7.78 8.8888 8.89 9.9999 10.00 Admin\ Savings\ Bank Outsider\ Trust].each do |text|
        assert_not_includes response.body, text
      end
    end

    def ai_usage(user, cost:, operation:, family: user.family)
      LlmUsage.create!(
        family: family, user: user, provider: "openai", model: "gpt-4.1", operation: operation,
        prompt_tokens: 10, completion_tokens: 5, total_tokens: 15, estimated_cost: cost, created_at: @month
      )
    end

    def plaid_usage(user, institution)
      PlaidItemUsage.create!(
        family: user.family, user: user, plaid_item_id: SecureRandom.uuid, period: "2026-10",
        institution_name: institution, billed_products: %w[transactions]
      )
    end
end
