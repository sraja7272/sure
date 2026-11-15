require "test_helper"

class Provider::ConnectorAvailabilityTest < ActiveSupport::TestCase
  setup do
    Setting.disabled_connectors = []
  end

  teardown do
    Setting.disabled_connectors = []
  end

  test "lists every registered connector once, keyed by provider" do
    keys = Provider::ConnectorAvailability.keys

    assert_equal Provider::Factory.registered_provider_types.size, keys.size
    assert_includes keys, "plaid"
    assert_includes keys, "simplefin"
    assert_includes keys, "financekit"
    assert_includes keys, "trading212"
    assert_not_includes keys, "plaid_eu"
  end

  test "every connector is on by default" do
    assert_equal Provider::ConnectorAvailability.keys.sort, Provider::ConnectorAvailability.enabled_keys.sort
    assert Provider::ConnectorAvailability.enabled?("simplefin")
  end

  test "update! turns off every connector not listed" do
    Provider::ConnectorAvailability.update!(%w[plaid])

    assert_equal %w[plaid], Provider::ConnectorAvailability.enabled_keys
    assert_not Provider::ConnectorAvailability.enabled?("simplefin")
  end

  test "plaid_eu follows the plaid switch" do
    Provider::ConnectorAvailability.update!(%w[simplefin])
    assert_not Provider::ConnectorAvailability.enabled?("plaid_eu")

    Provider::ConnectorAvailability.update!(%w[plaid_eu])
    assert Provider::ConnectorAvailability.enabled?("plaid")
  end

  test "update! refuses to turn every connector off" do
    assert_raises(Provider::ConnectorAvailability::NoneEnabledError) do
      Provider::ConnectorAvailability.update!([])
    end
    assert Provider::ConnectorAvailability.enabled?("plaid")
  end

  test "update! refuses unknown connectors" do
    assert_raises(Provider::ConnectorAvailability::UnknownConnectorError) do
      Provider::ConnectorAvailability.update!(%w[plaid not_a_connector])
    end
  end

  test "connect options leave out connectors that are off" do
    family = families(:dylan_family)
    keys_before = Provider::Factory.connection_configs_for_account_type(account_type: "Depository", family: family).map { |c| c[:key] }
    assert_includes keys_before, "simplefin"

    Provider::ConnectorAvailability.update!(Provider::ConnectorAvailability.keys - %w[simplefin])

    keys_after = Provider::Factory.connection_configs_for_account_type(account_type: "Depository", family: family).map { |c| c[:key] }
    assert_not_includes keys_after, "simplefin"
    assert_equal keys_before - %w[simplefin], keys_after
  end
end
