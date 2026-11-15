module UsageCostsHelper
  # Usage costs are recorded in USD whatever the family's currency. AI calls
  # often cost fractions of a cent, so their figures pass four places. Other
  # figures use two places, or four when they hold a fraction of a cent, so a
  # total that is mostly AI cost never rounds away to $0.00. A non-zero amount
  # that would still round to zero reads as less than the smallest unit shown,
  # such as "<$0.0001". The result is a plain string, so views escape the "<".
  def format_usage_cost(amount, precision: nil)
    amount = amount.to_d
    precision ||= amount.round(2) == amount ? 2 : 4

    if amount.nonzero? && amount.round(precision).zero?
      smallest_unit = format_money(Money.new(BigDecimal(10)**-precision, "USD"), precision: precision)
      return t("usage_costs.less_than", amount: smallest_unit)
    end

    format_money(Money.new(amount, "USD"), precision: precision)
  end

  # The Plaid rates form, grouped by the product each rate belongs to, in
  # display order. Covers every key of PlaidItemUsage::RATE_SETTINGS.
  PLAID_RATE_GROUPS = {
    transactions: %i[transactions transactions_refresh],
    investments: %i[investments_holdings investments_transactions],
    liabilities: %i[liabilities]
  }.freeze

  # Decimal places to show a Plaid rate with: cents at least, more when the
  # saved rate has them, so editing the form never rounds a sub-cent rate.
  def plaid_rate_precision(rate)
    [ rate.to_d.to_s("F").split(".").last.sub(/0+\z/, "").length, 2 ].max
  end

  # The block is captured before the partial renders, so lazy `t(".key")`
  # lookups in it resolve against the calling view, not the partial.
  def usage_cost_section(title:, &block)
    render "shared/usage_cost_section", title: title, content: capture(&block)
  end

  def usage_cost_operation_label(operation)
    t("usage_costs.operations.#{operation}", default: operation.to_s.humanize)
  end

  def usage_cost_products_label(products)
    products.map { |product| t("usage_costs.products.#{product}", default: product.to_s.humanize) }.to_sentence
  end
end
