require "test_helper"

class StyledFormBuilderTest < ActionView::TestCase
  setup do
    @builder = StyledFormBuilder.new(:account_statement, nil, self, {})
  end

  test "a labelled file field sits in a form field with its label" do
    field = Nokogiri::HTML.fragment(@builder.file_field(:files, label: "Statement files")).at(".form-field")

    assert field, "expected the file input wrapped in a .form-field"
    assert_equal "account_statement_files", field.at("label.form-field__label")["for"]
    assert_includes field.at("input[type=file]")["class"].split, "file:bg-container-inset"
  end

  # text-destructive inverts in dark mode; a raw palette class does not.
  test "a required field marks its label with the destructive token" do
    field = Nokogiri::HTML.fragment(@builder.text_field(:name, label: "Name", required: true))
    marker = field.at("label.form-field__label span")

    assert marker, "expected a required marker in the label"
    assert_equal "*", marker.text
    assert_includes marker["class"].split, "text-destructive"
  end

  # The dropzones pass `hidden` and draw their own target: no wrapper, and
  # their classes merged in rather than replaced.
  test "an unlabelled file field comes back bare and keeps the caller's classes" do
    fragment = Nokogiri::HTML.fragment(@builder.file_field(:files, class: "hidden"))

    assert_nil fragment.at(".form-field")
    assert_includes fragment.at("input[type=file]")["class"].split, "hidden"
  end

  test "a money field shows the calculator operators by default" do
    field = Nokogiri::HTML.fragment(@builder.money_field(:amount, label: "Amount", hide_currency: true))

    assert_equal 4, field.css("[data-action*='money-field#insertOperator']").size
  end

  test "a money field leaves the operators out with hide_operators" do
    field = Nokogiri::HTML.fragment(@builder.money_field(:amount, label: "Amount", hide_currency: true, hide_operators: true))

    assert_empty field.css("[data-action*='money-field#insertOperator']")
    assert field.at("input[name='account_statement[amount]']"), "expected the amount input to still render"
    assert_equal "$", field.at("[data-money-field-target='symbol']").text.strip
  end
end
