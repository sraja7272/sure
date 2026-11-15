# Plaid bills an item for every month it exists, whether or not it syncs, so
# broken and pending-deletion items are recorded too.
class RecordPlaidItemUsageJob < ApplicationJob
  queue_as :scheduled

  def perform
    PlaidItem.find_each do |plaid_item|
      plaid_item.record_usage
    end
  end
end
