require "test_helper"

class PlaidItemUsageTest < ActiveSupport::TestCase
  RATES = {
    transactions: BigDecimal("0.30"),
    transactions_refresh: BigDecimal("0.12"),
    investments_holdings: BigDecimal("0.18"),
    investments_transactions: BigDecimal("0.07"),
    liabilities: BigDecimal("0.20")
  }.freeze

  setup do
    @plaid_item = plaid_items(:one)
    @owner = users(:family_member)
    @plaid_item.update!(owner: @owner, billed_products: [ "transactions" ])
  end

  test "current_period is the year and month" do
    travel_to Date.new(2026, 3, 9) do
      assert_equal "2026-03", PlaidItemUsage.current_period
    end
  end

  test "record! creates one row for the item's month" do
    assert_difference "PlaidItemUsage.count", 1 do
      PlaidItemUsage.record!(@plaid_item, period: "2026-11")
    end

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert_equal @plaid_item.family, usage.family
    assert_equal @owner, usage.user
    assert_equal "Test Bank", usage.institution_name
    assert_equal "us", usage.plaid_region
    assert_equal [ "transactions" ], usage.billed_products
    assert_equal 0, usage.transactions_refresh_count
  end

  test "record! updates the month's row instead of duplicating it and keeps the refresh count" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")
    PlaidItemUsage.increment_refresh!(@plaid_item, period: "2026-11")

    admin = users(:family_admin)
    @plaid_item.update!(owner: admin, name: "Renamed Bank")

    assert_no_difference "PlaidItemUsage.count" do
      PlaidItemUsage.record!(@plaid_item, period: "2026-11")
    end

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert_equal admin, usage.user
    assert_equal "Renamed Bank", usage.institution_name
    assert_equal 1, usage.transactions_refresh_count
  end

  test "record! only adds billed products within a month" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")

    @plaid_item.update!(billed_products: [ "investments" ])
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert_equal %w[investments transactions], usage.billed_products.sort
  end

  test "record! starts a new row for a new month" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-10")

    assert_difference "PlaidItemUsage.count", 1 do
      PlaidItemUsage.record!(@plaid_item, period: "2026-11")
    end

    assert_equal %w[2026-10 2026-11], PlaidItemUsage.where(plaid_item_id: @plaid_item.id).order(:period).pluck(:period)
  end

  test "record! defaults to the current month" do
    travel_to Date.new(2026, 5, 20) do
      PlaidItemUsage.record!(@plaid_item)
    end

    assert PlaidItemUsage.exists?(plaid_item_id: @plaid_item.id, period: "2026-05")
  end

  test "increment_refresh! creates the month's row with the item's details" do
    assert_difference "PlaidItemUsage.count", 1 do
      PlaidItemUsage.increment_refresh!(@plaid_item, period: "2026-11")
    end

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert_equal 1, usage.transactions_refresh_count
    assert_equal @owner, usage.user
    assert_equal @plaid_item.family, usage.family
    assert_equal [ "transactions" ], usage.billed_products
  end

  test "increment_refresh! increments an existing row" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")

    assert_no_difference "PlaidItemUsage.count" do
      3.times { PlaidItemUsage.increment_refresh!(@plaid_item, period: "2026-11") }
    end

    assert_equal 3, PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11").transactions_refresh_count
  end

  test "the row outlives the Plaid item" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")

    plaid_provider = mock
    plaid_provider.stubs(:remove_item)
    Provider::Registry.stubs(:plaid_provider_for_region).returns(plaid_provider)

    @plaid_item.destroy!

    usage = PlaidItemUsage.find_by(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert usage.present?
    assert_equal "Test Bank", usage.institution_name
  end

  test "deleting the owner keeps the row without a user" do
    PlaidItemUsage.record!(@plaid_item, period: "2026-11")

    @owner.destroy!

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: "2026-11")
    assert_nil usage.user_id
  end

  test "rates are read from settings as decimals" do
    Setting.plaid_rate_transactions = "0.30"
    Setting.plaid_rate_transactions_refresh = "0.12"
    Setting.plaid_rate_investments_holdings = "0.18"
    Setting.plaid_rate_investments_transactions = "0.07"
    Setting.plaid_rate_liabilities = "0.20"

    rates = PlaidItemUsage.rates

    assert_equal BigDecimal("0.30"), rates[:transactions]
    assert_equal BigDecimal("0.12"), rates[:transactions_refresh]
    assert_equal BigDecimal("0.18"), rates[:investments_holdings]
    assert_equal BigDecimal("0.07"), rates[:investments_transactions]
    assert_equal BigDecimal("0.20"), rates[:liabilities]
    assert rates.values.all?(BigDecimal)
  end

  test "update_rates saves every rate" do
    assert PlaidItemUsage.update_rates(
      "transactions" => "0.30", "transactions_refresh" => " 0.12 ",
      "investments_holdings" => "0.18", "investments_transactions" => "0.07", "liabilities" => "0"
    )

    assert_equal(
      { transactions: BigDecimal("0.30"), transactions_refresh: BigDecimal("0.12"),
        investments_holdings: BigDecimal("0.18"), investments_transactions: BigDecimal("0.07"), liabilities: 0 },
      PlaidItemUsage.rates
    )
  end

  test "update_rates saves nothing when any rate is missing, negative or not a number" do
    valid = { transactions: "0.30", transactions_refresh: "0.12", investments_holdings: "0.18", investments_transactions: "0.07", liabilities: "0.20" }

    [ { investments_holdings: "-0.01" }, { investments_holdings: "abc" }, { investments_transactions: "" },
      { investments_transactions: "Infinity" }, { investments_transactions: nil } ].each do |bad|
      assert_not PlaidItemUsage.update_rates(valid.merge(bad))
      assert_equal 0, Setting.plaid_rate_transactions.to_d
    end
  end

  test "rates default to zero" do
    assert_equal(
      { transactions: 0, transactions_refresh: 0, investments_holdings: 0, investments_transactions: 0, liabilities: 0 },
      PlaidItemUsage.rates
    )
  end

  test "cost sums the billed products' monthly rates and the refresh calls" do
    usage = PlaidItemUsage.new(billed_products: %w[transactions liabilities], transactions_refresh_count: 3)

    cost = usage.cost(RATES)

    assert_kind_of BigDecimal, cost
    assert_equal BigDecimal("0.86"), cost
  end

  test "investments cost the holdings and investment transactions rates together" do
    usage = PlaidItemUsage.new(billed_products: %w[investments], transactions_refresh_count: 0)

    assert_equal BigDecimal("0.25"), usage.cost(RATES)
  end

  test "cost ignores products without a rate" do
    usage = PlaidItemUsage.new(billed_products: %w[auth identity liabilities], transactions_refresh_count: 0)

    assert_equal BigDecimal("0.20"), usage.cost(RATES)
  end

  test "cost reads the configured rates by default" do
    Setting.plaid_rate_liabilities = "0.25"
    usage = PlaidItemUsage.new(billed_products: %w[liabilities], transactions_refresh_count: 2)

    assert_equal BigDecimal("0.25"), usage.cost
  end
end
