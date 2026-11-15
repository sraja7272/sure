require "test_helper"

class RecordPlaidItemUsageJobTest < ActiveJob::TestCase
  setup do
    @family = families(:dylan_family)
    @healthy = plaid_items(:one)
    @broken = @family.plaid_items.create!(
      name: "Broken Bank", plaid_id: "item_broken", access_token: "token_broken", status: :requires_update
    )
    @deleting = @family.plaid_items.create!(
      name: "Leaving Bank", plaid_id: "item_deleting", access_token: "token_deleting", scheduled_for_deletion: true
    )
  end

  test "records every existing Plaid item for the current month" do
    RecordPlaidItemUsageJob.perform_now

    period = PlaidItemUsage.current_period
    [ @healthy, @broken, @deleting ].each do |item|
      assert PlaidItemUsage.exists?(plaid_item_id: item.id, period: period), "expected usage for #{item.name}"
    end
  end

  test "one failing item does not stop the rest" do
    PlaidItemUsage.expects(:record!).with { |item| item.id == @broken.id }.raises(ActiveRecord::StatementInvalid, "boom")
    PlaidItemUsage.expects(:record!).with { |item| item.id == @healthy.id }.once
    PlaidItemUsage.expects(:record!).with { |item| item.id == @deleting.id }.once

    assert_difference "DebugLogEntry.count", 1 do
      RecordPlaidItemUsageJob.perform_now
    end

    entry = DebugLogEntry.order(:created_at).last
    assert_equal "plaid", entry.provider_key
    assert_equal @family, entry.family
    assert_equal "ActiveRecord::StatementInvalid", entry.metadata["error_class"]
  end
end
