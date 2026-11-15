require "test_helper"

class UsageCostsHelperTest < ActionView::TestCase
  include ApplicationHelper, UsageCostsHelper

  test "whole-cent amounts keep two places" do
    assert_equal "$0.00", format_usage_cost(BigDecimal("0"))
    assert_equal "$1.50", format_usage_cost(BigDecimal("1.5"))
    assert_equal "$12.34", format_usage_cost(BigDecimal("12.34"))
  end

  test "amounts with a fraction of a cent show four places" do
    assert_equal "$0.0040", format_usage_cost(BigDecimal("0.004"))
    assert_equal "$1.2345", format_usage_cost(BigDecimal("1.2345"))
    assert_equal "$0.4321", format_usage_cost(BigDecimal("0.4321"))
  end

  test "an explicit precision always applies" do
    assert_equal "$1.5000", format_usage_cost(BigDecimal("1.5"), precision: 4)
    assert_equal "$0.0040", format_usage_cost(BigDecimal("0.004"), precision: 4)
  end
end
