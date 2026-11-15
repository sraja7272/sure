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

  test "a non-zero amount too small to show reads as less than the smallest unit" do
    assert_equal "<$0.0001", format_usage_cost(BigDecimal("0.00004"))
    assert_equal "<$0.0001", format_usage_cost(BigDecimal("0.00004"), precision: 4)
    assert_equal "<$0.01", format_usage_cost(BigDecimal("0.004"), precision: 2)
  end

  test "zero and the smallest shown unit keep their exact figure" do
    assert_equal "$0.0000", format_usage_cost(BigDecimal("0"), precision: 4)
    assert_equal "$0.0001", format_usage_cost(BigDecimal("0.0001"))
    assert_equal "$0.0001", format_usage_cost(BigDecimal("0.0001"), precision: 4)
  end

  test "the less-than figure is escaped when rendered" do
    assert_equal "&lt;$0.0001", ERB::Util.html_escape(format_usage_cost(BigDecimal("0.00004")))
  end
end
