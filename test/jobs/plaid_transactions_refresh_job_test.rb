require "test_helper"

class PlaidTransactionsRefreshJobTest < ActiveJob::TestCase
  setup do
    @plaid_item = plaid_items(:one)
    @plaid_item.update!(next_cursor: "saved-cursor")
    @provider = mock
    PlaidItem.any_instance.stubs(:plaid_provider).returns(@provider)
  end

  test "requests refresh and schedules cursor polling" do
    @provider.expects(:refresh_transactions).with(@plaid_item.access_token)

    assert_enqueued_with(
      job: PlaidTransactionsRefreshPollJob,
      args: [ @plaid_item, { cursor: "saved-cursor" } ]
    ) do
      PlaidTransactionsRefreshJob.perform_now(@plaid_item)
    end
  end

  test "still polls after an ambiguous refresh request failure" do
    @provider.expects(:refresh_transactions).raises(Timeout::Error)

    assert_difference "DebugLogEntry.count", 1 do
      assert_enqueued_with(job: PlaidTransactionsRefreshPollJob) do
        PlaidTransactionsRefreshJob.perform_now(@plaid_item)
      end
    end

    assert_equal "Timeout::Error", DebugLogEntry.order(:created_at).last.metadata["error_class"]
  end

  test "counts a successful refresh call for the month" do
    @provider.expects(:refresh_transactions).with(@plaid_item.access_token)

    PlaidTransactionsRefreshJob.perform_now(@plaid_item)

    usage = PlaidItemUsage.find_by!(plaid_item_id: @plaid_item.id, period: PlaidItemUsage.current_period)
    assert_equal 1, usage.transactions_refresh_count
  end

  test "does not count a refresh call that raised" do
    @provider.expects(:refresh_transactions).raises(Timeout::Error)

    PlaidTransactionsRefreshJob.perform_now(@plaid_item)

    assert_not PlaidItemUsage.exists?(plaid_item_id: @plaid_item.id)
  end

  test "still polls when counting the refresh call fails" do
    @provider.expects(:refresh_transactions)
    PlaidItemUsage.stubs(:increment_refresh!).raises(ActiveRecord::StatementInvalid, "boom")

    assert_difference "DebugLogEntry.count", 1 do
      assert_enqueued_with(job: PlaidTransactionsRefreshPollJob) do
        PlaidTransactionsRefreshJob.perform_now(@plaid_item)
      end
    end

    entry = DebugLogEntry.order(:created_at).last
    assert_equal "plaid", entry.provider_key
    assert_equal "ActiveRecord::StatementInvalid", entry.metadata["error_class"]
  end
end
