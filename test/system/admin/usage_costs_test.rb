require "application_system_test_case"

class Admin::UsageCostsTest < ApplicationSystemTestCase
  setup do
    sign_in users(:sure_support_staff)
  end

  # The rate fields are step="any" money fields with min_precision: 2, so
  # money_field_controller pads a short rate to cents on blur without
  # rounding away a sub-cent one.
  test "a rate field shows at least two decimals once it loses focus" do
    visit admin_usage_costs_path

    fill_in "plaid_rates[transactions]", with: ".2"
    find_field("plaid_rates[transactions]").send_keys(:tab)
    assert_field "plaid_rates[transactions]", with: "0.20"

    fill_in "plaid_rates[investments_holdings]", with: "0.125"
    find_field("plaid_rates[investments_holdings]").send_keys(:tab)
    assert_field "plaid_rates[investments_holdings]", with: "0.125"
  end
end
