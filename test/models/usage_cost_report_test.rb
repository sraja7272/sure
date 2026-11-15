require "test_helper"

class UsageCostReportTest < ActiveSupport::TestCase
  RATES = {
    transactions: BigDecimal("0.30"),
    transactions_refresh: BigDecimal("0.12"),
    investments_holdings: BigDecimal("0.15"),
    investments_transactions: BigDecimal("0.05"),
    liabilities: BigDecimal("0.10")
  }.freeze

  setup do
    @dylan = families(:dylan_family)
    @other_family = families(:empty)
    @admin = users(:family_admin)
    @member = users(:family_member)
    @outsider = users(:josh)
    @month = Date.new(2026, 10, 1)

    PlaidItemUsage.stubs(:rates).returns(RATES)
  end

  test "sums AI and Plaid cost per user" do
    ai_usage(@member, cost: "0.25")
    ai_usage(@member, cost: "0.50", operation: "auto_categorize")
    plaid_usage(@member, products: %w[transactions investments], refreshes: 2)

    line = report.lines.find { |l| l.user == @member }

    assert_equal @dylan, line.family
    assert_equal BigDecimal("0.75"), line.ai_cost
    assert_equal 2, line.ai_requests
    assert_equal 0, line.ai_unpriced_requests
    assert_equal 1, line.plaid_items
    assert_equal BigDecimal("0.74"), line.plaid_cost
    assert_equal BigDecimal("1.49"), line.total
    assert_kind_of BigDecimal, line.ai_cost
  end

  test "includes users with only Plaid usage and omits users with none" do
    plaid_usage(@admin, products: %w[liabilities])

    assert_equal [ @admin ], report.lines.map(&:user)
    assert_equal BigDecimal("0"), report.lines.first.ai_cost
  end

  test "rows without a user form one unassigned line per family" do
    ai_usage(nil, cost: "0.10")
    ai_usage(nil, cost: "0.20")
    plaid_usage(nil, products: %w[transactions])
    ai_usage(nil, cost: "1.00", family: @other_family)

    unassigned = report.lines.select(&:unassigned?)

    assert_equal [ @dylan, @other_family ].sort_by(&:name), unassigned.map(&:family)
    dylan_line = unassigned.find { |l| l.family == @dylan }
    assert_nil dylan_line.user
    assert_equal BigDecimal("0.30"), dylan_line.ai_cost
    assert_equal 2, dylan_line.ai_requests
    assert_equal BigDecimal("0.30"), dylan_line.plaid_cost
  end

  test "counts requests on models without pricing as unpriced" do
    ai_usage(@member, cost: nil)
    ai_usage(@member, cost: "0.05")

    line = report.lines.sole

    assert_equal 2, line.ai_requests
    assert_equal 1, line.ai_unpriced_requests
    assert_equal BigDecimal("0.05"), line.ai_cost
  end

  test "leaves failed calls out of requests and unpriced counts" do
    ai_usage(@member, cost: "0.05")
    ai_usage(@member, cost: nil, metadata: { "error" => "rate limited", "http_status_code" => 429 })

    line = report.lines.sole

    assert_equal 1, line.ai_requests
    assert_equal 0, line.ai_unpriced_requests
  end

  test "a user with only failed calls has no line" do
    ai_usage(@member, cost: nil, metadata: { "error" => "timeout" })

    assert_empty report.lines
  end

  test "only counts AI rows inside the UTC calendar month, whatever the time zone" do
    Time.use_zone("America/New_York") do
      ai_usage(@member, cost: "1.00", at: Time.utc(2026, 10, 1, 0, 30))
      ai_usage(@member, cost: "2.00", at: Time.utc(2026, 10, 31, 23, 30))
      ai_usage(@member, cost: "4.00", at: Time.utc(2026, 9, 30, 23, 30))
      ai_usage(@member, cost: "8.00", at: Time.utc(2026, 11, 1, 0, 30))

      assert_equal BigDecimal("3.00"), report.lines.sole.ai_cost
    end
  end

  test "the current month is the UTC month, whatever the time zone" do
    # 8pm on 31 October in Los Angeles is already November in UTC.
    Time.use_zone("America/Los_Angeles") do
      travel_to Time.utc(2026, 11, 1, 3) do
        assert_equal Date.new(2026, 11, 1), UsageCostReport.current_month
        assert_equal Date.new(2026, 11, 1), UsageCostReport.new.month
        assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: "garbage").month
        assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: "2026-10").next_month
        assert_nil UsageCostReport.new(month: "2026-11").next_month
      end
    end

    # 5am on 1 November in Tokyo is still October in UTC.
    Time.use_zone("Asia/Tokyo") do
      travel_to Time.utc(2026, 10, 31, 20) do
        assert_equal Date.new(2026, 10, 1), UsageCostReport.new.month
        assert_nil UsageCostReport.new(month: "2026-10").next_month
      end
    end
  end

  test "a time picks the UTC month it falls in" do
    late_october_in_los_angeles = Time.utc(2026, 11, 1, 3).in_time_zone("America/Los_Angeles")

    assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: late_october_in_los_angeles).month
  end

  test "the month's AI rows near a boundary are the same in every time zone" do
    ai_usage(@member, cost: "1.00", at: Time.utc(2026, 10, 31, 23, 30))
    ai_usage(@member, cost: "2.00", at: Time.utc(2026, 11, 1, 0, 30))

    costs = %w[UTC America/Los_Angeles Asia/Tokyo].map do |zone|
      Time.use_zone(zone) { report.lines.sole.ai_cost }
    end

    assert_equal [ BigDecimal("1.00") ] * 3, costs
  end

  test "only counts Plaid rows for the month's period" do
    plaid_usage(@member, products: %w[transactions], period: "2026-09")
    plaid_usage(@member, products: %w[investments], period: "2026-10")

    line = report.lines.sole

    assert_equal 1, line.plaid_items
    assert_equal BigDecimal("0.20"), line.plaid_cost
  end

  test "scopes to a family" do
    ai_usage(@member, cost: "0.10")
    ai_usage(@outsider, cost: "0.20", family: @other_family)

    assert_equal [ @member ], report(family: @dylan).lines.map(&:user)
  end

  test "scopes to a user, without the family's unassigned line" do
    ai_usage(@member, cost: "0.10")
    ai_usage(@admin, cost: "0.20")
    ai_usage(nil, cost: "0.40")
    plaid_usage(@admin, products: %w[transactions])

    scoped = report(user: @member)

    assert_equal [ @member ], scoped.lines.map(&:user)
    assert_equal BigDecimal("0.10"), scoped.grand_total.total
  end

  test "groups by family name then user name with subtotals and a grand total" do
    ai_usage(@member, cost: "0.10")
    ai_usage(@admin, cost: "0.20")
    ai_usage(nil, cost: "0.05")
    ai_usage(@outsider, cost: "1.00", family: @other_family)
    plaid_usage(@admin, products: %w[transactions])

    groups = report.groups

    assert_equal [ @other_family, @dylan ], groups.map(&:family) # "Family" before "The Dylan Family"
    dylan = groups.last
    assert_equal [ @admin, @member, nil ], dylan.lines.map(&:user) # Bob, Jakob, then unassigned
    assert_equal BigDecimal("0.35"), dylan.subtotal.ai_cost
    assert_equal BigDecimal("0.30"), dylan.subtotal.plaid_cost
    assert_equal BigDecimal("0.65"), dylan.subtotal.total
    assert_equal 3, dylan.subtotal.ai_requests

    assert_equal BigDecimal("1.65"), report.grand_total.total
    assert_equal 4, report.grand_total.ai_requests
    assert_equal 1, report.grand_total.plaid_items
  end

  test "applies the configured Plaid rates" do
    PlaidItemUsage.unstub(:rates)
    Setting.plaid_rate_transactions = "1.50"
    Setting.plaid_rate_transactions_refresh = "0.25"
    plaid_usage(@member, products: %w[transactions], refreshes: 4)

    assert_equal BigDecimal("2.50"), report.lines.sole.plaid_cost
  ensure
    Setting.where(var: %w[plaid_rate_transactions plaid_rate_transactions_refresh]).delete_all
    Setting.clear_cache
  end

  test "breaks a user's AI cost down by operation" do
    ai_usage(@member, cost: "0.10", operation: "chat")
    ai_usage(@member, cost: "0.30", operation: "chat")
    ai_usage(@member, cost: nil, operation: "auto_categorize")
    ai_usage(@admin, cost: "5.00", operation: "chat")

    by_operation = report(user: @member).ai_cost_by_operation

    assert_equal %w[chat auto_categorize], by_operation.map(&:operation)
    chat = by_operation.first
    assert_equal BigDecimal("0.40"), chat.ai_cost
    assert_equal 2, chat.ai_requests
    assert_equal 1, by_operation.last.ai_unpriced_requests
  end

  test "lists a user's Plaid rows with their cost" do
    plaid_usage(@member, products: %w[transactions], refreshes: 1, institution: "First Bank")
    plaid_usage(@admin, products: %w[transactions], institution: "Admin Bank")

    rows = report(user: @member).plaid_rows

    assert_equal [ "First Bank" ], rows.map(&:institution_name)
    assert_equal BigDecimal("0.42"), rows.first.cost
    assert_equal [ "transactions" ], rows.first.billed_products
    assert_equal 1, rows.first.transactions_refresh_count
  end

  test "parses the month and falls back to the current month" do
    travel_to Time.zone.local(2026, 11, 15, 12) do
      assert_equal Date.new(2026, 3, 1), UsageCostReport.new(month: "2026-03").month
      assert_equal Date.new(2026, 3, 1), UsageCostReport.new(month: Date.new(2026, 3, 17)).month
      assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: "2026-13").month
      assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: "garbage").month
      assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: nil).month
      assert_equal Date.new(2026, 11, 1), UsageCostReport.new.month
      assert_equal "2026-11", UsageCostReport.new.period
    end
  end

  test "next_month is nil once it would be in the future" do
    travel_to Time.zone.local(2026, 11, 15, 12) do
      assert_equal Date.new(2026, 10, 1), UsageCostReport.new(month: "2026-11").previous_month
      assert_nil UsageCostReport.new(month: "2026-11").next_month
      assert_equal Date.new(2026, 11, 1), UsageCostReport.new(month: "2026-10").next_month
    end
  end

  test "to_csv has one row per line" do
    ai_usage(@member, cost: "0.123456")
    ai_usage(@member, cost: nil)
    ai_usage(nil, cost: "0.10")
    plaid_usage(@member, products: %w[transactions])

    rows = CSV.parse(report.to_csv)

    assert_equal [ "Period", "Family", "Person", "Email", "AI cost (USD)", "AI requests", "Unpriced AI requests", "Plaid items", "Plaid cost (USD)", "Total (USD)" ], rows.first
    assert_equal [ "2026-10", "The Dylan Family", "Jakob Dylan", "jakobdylan@yahoo.com", "0.1235", "2", "1", "1", "0.3000", "0.4235" ], rows.second
    assert_equal [ "2026-10", "The Dylan Family", "Unassigned", nil, "0.1000", "1", "0", "0", "0.0000", "0.1000" ], rows.third
    assert_equal 3, rows.size
  end

  test "to_csv neutralises text cells a spreadsheet would read as a formula" do
    @member.update!(first_name: "=1+1")
    @dylan.update!(name: "@SUM(A1)")
    ai_usage(@member, cost: "0.10")

    row = CSV.parse(report.to_csv).second

    assert_equal [ "2026-10", "'@SUM(A1)", "'=1+1 Dylan", "jakobdylan@yahoo.com", "0.1000" ], row.first(5)
  end

  test "to_csv leaves ordinary names unchanged" do
    @member.update!(first_name: "Mary-Jane")
    ai_usage(@member, cost: "0.10")

    row = CSV.parse(report.to_csv).second

    assert_equal [ "The Dylan Family", "Mary-Jane Dylan" ], row[1, 2]
  end

  private
    def report(**scope)
      UsageCostReport.new(month: @month, **scope)
    end

    def ai_usage(user, cost:, family: @dylan, operation: "chat", metadata: {}, at: Time.zone.local(2026, 10, 15, 12))
      LlmUsage.create!(
        family: family,
        user: user,
        provider: "openai",
        model: "gpt-4.1",
        operation: operation,
        prompt_tokens: 100,
        completion_tokens: 50,
        total_tokens: 150,
        estimated_cost: cost,
        metadata: metadata,
        created_at: at
      )
    end

    def plaid_usage(user, products:, refreshes: 0, period: "2026-10", family: @dylan, institution: "Test Bank")
      PlaidItemUsage.create!(
        family: family,
        user: user,
        plaid_item_id: SecureRandom.uuid,
        period: period,
        institution_name: institution,
        billed_products: products,
        transactions_refresh_count: refreshes
      )
    end
end
