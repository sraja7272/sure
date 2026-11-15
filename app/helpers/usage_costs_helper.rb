module UsageCostsHelper
  # Usage costs are recorded in USD whatever the family's currency. AI calls
  # often cost fractions of a cent, so their figures keep four places.
  def format_usage_cost(amount, precision: 2)
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

  def usage_cost_operation_label(operation)
    t("usage_costs.operations.#{operation}", default: operation.to_s.humanize)
  end

  def usage_cost_products_label(products)
    products.map { |product| t("usage_costs.products.#{product}", default: product.to_s.humanize) }.to_sentence
  end
end
