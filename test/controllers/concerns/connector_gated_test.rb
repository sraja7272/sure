require "test_helper"

class ConnectorGatedTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    Setting.disabled_connectors = []
  end

  teardown do
    Setting.disabled_connectors = []
  end

  test "new connection is refused when the connector is off" do
    Provider::ConnectorAvailability.update!(%w[plaid])

    get new_simplefin_item_path

    assert_redirected_to accounts_path
    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "creating a connection is refused when the connector is off" do
    Provider::ConnectorAvailability.update!(%w[plaid])

    assert_no_difference "SimplefinItem.count" do
      post simplefin_items_path, params: { simplefin_item: { setup_token: "token" } }
    end
    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "existing connections can still be synced when the connector is off" do
    item = SimplefinItem.create!(family: @family, name: "Existing", access_url: "https://example.com/access")
    Provider::ConnectorAvailability.update!(%w[plaid])

    assert_difference "Sync.count", 1 do
      post sync_simplefin_item_path(item)
    end
    assert_not_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "plaid new connection is refused when plaid is off" do
    Provider::ConnectorAvailability.update!(%w[simplefin])

    get new_plaid_item_path(region: "us")

    assert_redirected_to accounts_path
    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end
end
