# Monthly ledger of what Plaid bills for each item: one row per item per
# calendar month. Plaid charges a subscription per item per billed product for
# every month the item exists, plus a fee per /transactions/refresh call. Rows
# keep plaid_item_id without a foreign key so they survive the item's deletion.
class PlaidItemUsage < ApplicationRecord
  # The monthly rates each billed product costs. Investments is billed as two
  # products, holdings and investment transactions, and every sync of an item
  # with investments calls both.
  MONTHLY_RATES = {
    "transactions" => %i[transactions],
    "investments" => %i[investments_holdings investments_transactions],
    "liabilities" => %i[liabilities]
  }.freeze

  PRICED_PRODUCTS = MONTHLY_RATES.keys.freeze

  RATE_SETTINGS = {
    transactions: :plaid_rate_transactions,
    transactions_refresh: :plaid_rate_transactions_refresh,
    investments_holdings: :plaid_rate_investments_holdings,
    investments_transactions: :plaid_rate_investments_transactions,
    liabilities: :plaid_rate_liabilities
  }.freeze

  belongs_to :family
  belongs_to :user, optional: true

  validates :plaid_item_id, :period, presence: true
  validates :period, uniqueness: { scope: :plaid_item_id }

  class << self
    def current_period
      Date.current.strftime("%Y-%m")
    end

    # Billed products only accumulate within a month: once Plaid has billed a
    # product for the month, dropping it later does not refund it.
    def record!(plaid_item, period: current_period)
      upsert(
        row_for(plaid_item, period),
        unique_by: %i[plaid_item_id period],
        on_duplicate: Arel.sql(<<~SQL.squish)
          family_id = EXCLUDED.family_id,
          user_id = EXCLUDED.user_id,
          institution_name = EXCLUDED.institution_name,
          plaid_region = EXCLUDED.plaid_region,
          billed_products = ARRAY(
            SELECT DISTINCT product
            FROM unnest(plaid_item_usages.billed_products || EXCLUDED.billed_products) AS product
            ORDER BY product
          ),
          updated_at = CURRENT_TIMESTAMP
        SQL
      )
    end

    def increment_refresh!(plaid_item, period: current_period)
      upsert(
        row_for(plaid_item, period).merge(transactions_refresh_count: 1),
        unique_by: %i[plaid_item_id period],
        on_duplicate: Arel.sql("transactions_refresh_count = plaid_item_usages.transactions_refresh_count + 1, updated_at = CURRENT_TIMESTAMP")
      )
    end

    # USD per item per month for each product, and per refresh call.
    def rates
      RATE_SETTINGS.transform_values { |setting| Setting.public_send(setting).to_d }
    end

    # Saves every rate, or none when any is missing, negative or not a number.
    def update_rates(values)
      values = values.to_h.symbolize_keys
      parsed = RATE_SETTINGS.keys.index_with { |key| parse_rate(values[key]) }
      return false if parsed.values.any?(&:nil?)

      parsed.each { |key, rate| Setting.public_send("#{RATE_SETTINGS.fetch(key)}=", rate) }
      true
    end

    private
      def parse_rate(value)
        rate = BigDecimal(value.to_s.strip)
        rate if rate.finite? && rate >= 0
      rescue ArgumentError
        nil
      end

      def row_for(plaid_item, period)
        {
          family_id: plaid_item.family_id,
          user_id: plaid_item.owner_id,
          plaid_item_id: plaid_item.id,
          period: period,
          institution_name: plaid_item.name,
          plaid_region: plaid_item.plaid_region,
          billed_products: Array(plaid_item.billed_products).map(&:to_s).uniq.sort
        }
      end
  end

  def cost(rates = self.class.rates)
    monthly_keys = (billed_products.uniq & PRICED_PRODUCTS).flat_map { |product| MONTHLY_RATES.fetch(product) }
    monthly_cost = monthly_keys.sum(BigDecimal("0")) { |key| rates.fetch(key, 0).to_d }

    monthly_cost + transactions_refresh_count * rates.fetch(:transactions_refresh, 0).to_d
  end
end
