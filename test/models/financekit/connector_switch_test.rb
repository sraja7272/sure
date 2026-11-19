require "test_helper"
require_relative "../../support/financekit_test_helper"

class Financekit::ConnectorSwitchTest < ActiveSupport::TestCase
  include FinancekitTestHelper

  setup { financekit_setup }

  teardown { Setting.enabled_connectors = nil }

  test "a second replacement of the same connection can't activate once the first has" do
    first = replacement_for(@item)
    second = replacement_for(@item)
    Provider::ConnectorAvailability.update!(%w[plaid])

    # The first replacement activating revokes the connection both named.
    @item.revoke!

    error = assert_raises(Financekit::Error) { second.activate! }
    assert_equal "connector_disabled", error.code
    assert_equal "pending_mapping", second.reload.status
    assert first.persisted?
  end

  test "a replacement of a live connection passes the switch while FinanceKit is off" do
    replacement = replacement_for(@item)
    Provider::ConnectorAvailability.update!(%w[plaid])

    # It gets past the switch and stops at the next rule: no accounts mapped yet.
    error = assert_raises(Financekit::Error) { replacement.activate! }
    assert_equal "account_setup_required", error.code
  end

  test "an enrollment started before FinanceKit was switched off can't activate as a new connection" do
    fresh = Financekit::Enrollment.create!(@user, @enrollment.merge("enrollment_id" => SecureRandom.uuid)).item
    Provider::ConnectorAvailability.update!(%w[plaid])

    error = assert_raises(Financekit::Error) { fresh.activate! }
    assert_equal "connector_disabled", error.code
  end

  private
    def replacement_for(item)
      Financekit::Enrollment.create!(@user,
        @enrollment.merge("enrollment_id" => SecureRandom.uuid, "replaces_connection_id" => item.id)).item
    end
end
