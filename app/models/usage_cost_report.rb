require "csv"

# Estimated AI and Plaid cost for one calendar month, per person. AI figures
# come from llm_usages (created_at within the month in the app time zone),
# Plaid figures from the plaid_item_usages ledger priced at the configured
# rates. Rows without a user become one "unassigned" line per family.
#
# Failed AI calls (an error recorded, no cost) are left out entirely: they
# cost nothing, and counting them as unpriced would suggest a missing price.
class UsageCostReport
  ZERO = BigDecimal("0")

  CSV_HEADERS = [
    "Period", "Family", "Person", "Email", "AI cost (USD)", "AI requests",
    "Unpriced AI requests", "Plaid items", "Plaid cost (USD)", "Total (USD)"
  ].freeze

  Totals = Data.define(:ai_cost, :ai_requests, :ai_unpriced_requests, :plaid_items, :plaid_cost) do
    def self.sum(items)
      new(
        ai_cost: items.sum(ZERO, &:ai_cost),
        ai_requests: items.sum(0, &:ai_requests),
        ai_unpriced_requests: items.sum(0, &:ai_unpriced_requests),
        plaid_items: items.sum(0, &:plaid_items),
        plaid_cost: items.sum(ZERO, &:plaid_cost)
      )
    end

    def total
      ai_cost + plaid_cost
    end
  end

  Line = Data.define(:family, :user, :ai_cost, :ai_requests, :ai_unpriced_requests, :plaid_items, :plaid_cost) do
    def total
      ai_cost + plaid_cost
    end

    def unassigned?
      user.nil?
    end
  end

  FamilyGroup = Data.define(:family, :lines) do
    def subtotal
      Totals.sum(lines)
    end
  end

  OperationLine = Data.define(:operation, :ai_cost, :ai_requests, :ai_unpriced_requests)

  PlaidRow = Data.define(:usage, :cost) do
    delegate :institution_name, :billed_products, :transactions_refresh_count, :plaid_region, to: :usage
  end

  attr_reader :month, :family, :user

  # @param month [Date, String, nil] any date in the month, or "YYYY-MM";
  #   anything else means the current month
  # @param family [Family, nil] limit to one family
  # @param user [User, nil] limit to one person's rows (no unassigned line)
  def initialize(month: nil, family: nil, user: nil)
    @month = self.class.parse_month(month)
    @family = family
    @user = user
  end

  def self.parse_month(value)
    case value
    when Date, Time, ActiveSupport::TimeWithZone
      value.to_date.beginning_of_month
    when /\A(\d{4})-(\d{2})\z/
      Date.new($1.to_i, $2.to_i, 1)
    else
      Date.current.beginning_of_month
    end
  rescue Date::Error
    Date.current.beginning_of_month
  end

  def period
    month.strftime("%Y-%m")
  end

  def previous_month
    month.prev_month
  end

  # nil when the next month hasn't started yet.
  def next_month
    month.next_month unless month.next_month > Date.current
  end

  def lines
    @lines ||= build_lines
  end

  def groups
    @groups ||= lines.chunk_while { |a, b| a.family == b.family }.map do |family_lines|
      FamilyGroup.new(family: family_lines.first.family, lines: family_lines)
    end
  end

  def grand_total
    Totals.sum(lines)
  end

  def ai_cost_by_operation
    ai_scope
      .group(:operation)
      .order(Arel.sql("COALESCE(SUM(estimated_cost), 0) DESC"), :operation)
      .pluck(:operation, *ai_aggregates)
      .map do |operation, cost, requests, unpriced|
        OperationLine.new(operation: operation, ai_cost: cost.to_d, ai_requests: requests, ai_unpriced_requests: unpriced)
      end
  end

  def plaid_rows
    @plaid_rows ||= plaid_usages.sort_by { |usage| usage.institution_name.to_s.downcase }.map do |usage|
      PlaidRow.new(usage: usage, cost: usage.cost(rates))
    end
  end

  def to_csv
    CSV.generate do |csv|
      csv << CSV_HEADERS
      lines.each do |line|
        csv << [
          period,
          line.family.name,
          line.unassigned? ? "Unassigned" : line.user.display_name,
          line.user&.email,
          decimal(line.ai_cost),
          line.ai_requests,
          line.ai_unpriced_requests,
          line.plaid_items,
          decimal(line.plaid_cost),
          decimal(line.total)
        ]
      end
    end
  end

  private
    def rates
      @rates ||= PlaidItemUsage.rates
    end

    def month_range
      month.in_time_zone.beginning_of_month..month.in_time_zone.end_of_month
    end

    def ai_scope
      scope = LlmUsage
        .where(created_at: month_range)
        .where("llm_usages.estimated_cost IS NOT NULL OR NULLIF(llm_usages.metadata ->> 'error', '') IS NULL")
      scope = scope.where(family_id: family.id) if family
      scope = scope.where(user_id: user.id) if user
      scope
    end

    def ai_aggregates
      [
        Arel.sql("COALESCE(SUM(llm_usages.estimated_cost), 0)"),
        Arel.sql("COUNT(*)"),
        Arel.sql("COUNT(*) FILTER (WHERE llm_usages.estimated_cost IS NULL)")
      ]
    end

    def plaid_usages
      @plaid_usages ||= begin
        scope = PlaidItemUsage.where(period: period)
        scope = scope.where(family_id: family.id) if family
        scope = scope.where(user_id: user.id) if user
        scope.to_a
      end
    end

    def build_lines
      ai = ai_scope.group(:family_id, :user_id).pluck(:family_id, :user_id, *ai_aggregates)
        .to_h { |family_id, user_id, cost, requests, unpriced| [ [ family_id, user_id ], [ cost.to_d, requests, unpriced ] ] }
      plaid = plaid_usages.group_by { |usage| [ usage.family_id, usage.user_id ] }

      keys = (ai.keys + plaid.keys).uniq
      families = Family.where(id: keys.map(&:first).uniq).index_by(&:id)
      users = User.where(id: keys.filter_map(&:last).uniq).index_by(&:id)

      keys.filter_map do |family_id, user_id|
        next unless (line_family = families[family_id])

        ai_cost, ai_requests, ai_unpriced = ai.fetch([ family_id, user_id ], [ ZERO, 0, 0 ])
        plaid_rows = plaid.fetch([ family_id, user_id ], [])

        Line.new(
          family: line_family,
          user: users[user_id],
          ai_cost: ai_cost,
          ai_requests: ai_requests,
          ai_unpriced_requests: ai_unpriced,
          plaid_items: plaid_rows.size,
          plaid_cost: plaid_rows.sum(ZERO) { |usage| usage.cost(rates) }
        )
      end.sort_by { |line| sort_key(line) }
    end

    def sort_key(line)
      [
        line.family.name.to_s.downcase,
        line.family.id,
        line.unassigned? ? 1 : 0,
        line.user&.display_name.to_s.downcase
      ]
    end

    def decimal(value)
      format("%.4f", value.round(4))
    end
end
