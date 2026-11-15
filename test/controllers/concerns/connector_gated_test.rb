require "test_helper"

class ConnectorGatedTest < ActionDispatch::IntegrationTest
  setup do
    sign_in users(:family_admin)
    @family = families(:dylan_family)
    Setting.enabled_connectors = nil
  end

  teardown do
    Setting.enabled_connectors = nil
  end

  test "every connector with a web connect flow gates its controller" do
    # FinanceKit enrolls through the API instead (Financekit::Enrollment).
    (Provider::ConnectorAvailability.keys - %w[financekit]).each do |key|
      controller = "#{key.camelize}ItemsController".safe_constantize
      assert controller, "#{key} has no #{key.camelize}ItemsController"
      assert_equal key, controller.gated_connector_key, "#{controller} does not gate the #{key} connector"
    end
    assert_equal "brex", BrexItems::AccountFlowsController.gated_connector_key
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

  test "relinking an account already linked through the connector stays allowed when it is off" do
    item = SimplefinItem.create!(family: @family, name: "Existing", access_url: "https://example.com/access")
    simplefin_account = item.simplefin_accounts.create!(name: "Checking", account_id: "sf-1", account_type: "checking", currency: "USD", current_balance: 10)
    account = @family.accounts.create!(name: "Checking", balance: 10, currency: "USD", accountable: Depository.new)
    AccountProvider.create!(account: account, provider: simplefin_account)
    Provider::ConnectorAvailability.update!(%w[plaid])

    get select_existing_account_simplefin_items_path(account_id: account.id)

    assert_not_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "linking an unlinked account is refused when the connector is off" do
    account = @family.accounts.create!(name: "Manual", balance: 0, currency: "USD", accountable: Depository.new)
    Provider::ConnectorAvailability.update!(%w[plaid])

    get select_existing_account_simplefin_items_path(account_id: account.id)

    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "plaid new connection is refused when plaid is off" do
    Provider::ConnectorAvailability.update!(%w[simplefin])

    get new_plaid_item_path(region: "us")

    assert_redirected_to accounts_path
    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "enable banking refuses to authorize a new connection when it is off" do
    item = @family.enable_banking_items.create!(name: "Existing", country_code: "DE", application_id: "app",
      client_certificate: OpenSSL::PKey::RSA.new(2048).to_pem)
    Provider::ConnectorAvailability.update!(%w[plaid])

    assert_no_difference "EnableBankingItem.count" do
      post authorize_enable_banking_item_path(item), params: { aspsp_name: "Some Bank", new_connection: "true" }
    end
    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end

  test "snaptrade refuses to start a first connection when it is off" do
    @family.snaptrade_items.destroy_all
    Provider::Snaptrade.stubs(:authorization_code_configured?).returns(true)
    Provider::Snaptrade.stubs(:oauth_configured?).returns(true)
    Provider::ConnectorAvailability.update!(%w[plaid])

    assert_no_difference "SnaptradeItem.count" do
      get oauth_authorize_snaptrade_items_path
    end
    assert_equal I18n.t("connectors.disabled"), flash[:alert]

    assert_no_difference "SnaptradeItem.count" do
      post start_oauth_device_flow_snaptrade_items_path
    end
  end

  test "brex account flows are refused when brex is off" do
    Provider::ConnectorAvailability.update!(%w[plaid])

    get select_accounts_brex_items_path(accountable_type: "Depository")

    assert_equal I18n.t("connectors.disabled"), flash[:alert]
  end
end
