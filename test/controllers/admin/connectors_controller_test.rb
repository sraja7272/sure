require "test_helper"

class Admin::ConnectorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ensure_tailwind_build
    Setting.disabled_connectors = []
  end

  teardown do
    Setting.disabled_connectors = []
    Setting.connectors_last_save = nil
  end

  test "super admin sees a switch for every connector" do
    sign_in users(:sure_support_staff)

    get admin_connectors_path

    assert_response :success
    assert_select "form[data-controller='connector-switches']"
    assert_select "template[data-connector-switches-target='notice']"
    Provider::ConnectorAvailability.keys.each do |key|
      assert_select "input[type=checkbox][name='connectors[#{key}]'][data-action='change->connector-switches#save']"
    end
  end

  test "family admins cannot open the page" do
    sign_in users(:family_admin)

    get admin_connectors_path
    assert_redirected_to root_path

    patch admin_connectors_path, params: { connectors: { plaid: "1" } }
    assert_redirected_to root_path
    assert_empty Setting.disabled_connectors
  end

  test "saving turns off unchecked connectors" do
    sign_in users(:sure_support_staff)
    params = Provider::ConnectorAvailability.keys.index_with { "0" }.merge("plaid" => "1")

    patch admin_connectors_path, params: { connectors: params }

    assert_redirected_to admin_connectors_path
    assert_equal %w[plaid], Provider::ConnectorAvailability.enabled_keys
  end

  test "an auto-save answers with no content, so no notification and no redraw" do
    sign_in users(:sure_support_staff)
    params = Provider::ConnectorAvailability.keys.index_with { "0" }.merge("plaid" => "1")

    patch admin_connectors_path, params: { connectors: params, client_id: "page-1", sequence: 1 }, as: :turbo_stream

    assert_response :no_content
    assert_empty response.body
    assert_equal %w[plaid], Provider::ConnectorAvailability.enabled_keys
  end

  test "an auto-save that arrives after a newer one from the same page is ignored" do
    sign_in users(:sure_support_staff)
    only_plaid = Provider::ConnectorAvailability.keys.index_with { "0" }.merge("plaid" => "1")
    plaid_and_simplefin = only_plaid.merge("simplefin" => "1")

    patch admin_connectors_path, params: { connectors: plaid_and_simplefin, client_id: "page-1", sequence: 2 }, as: :turbo_stream
    patch admin_connectors_path, params: { connectors: only_plaid, client_id: "page-1", sequence: 1 }, as: :turbo_stream

    assert_response :no_content
    assert_equal %w[plaid simplefin], Provider::ConnectorAvailability.enabled_keys.sort
  end

  test "an auto-save turning every connector off restores the switches" do
    sign_in users(:sure_support_staff)
    params = Provider::ConnectorAvailability.keys.index_with { "0" }

    patch admin_connectors_path, params: { connectors: params, client_id: "page-1", sequence: 1 }, as: :turbo_stream

    assert_response :unprocessable_entity
    assert_includes response.body, %(target="connector_switches")
    assert_includes response.body, I18n.t("admin.connectors.update.none_enabled")
    assert_empty Setting.disabled_connectors
  end

  test "saving with every connector off is refused" do
    sign_in users(:sure_support_staff)
    params = Provider::ConnectorAvailability.keys.index_with { "0" }

    patch admin_connectors_path, params: { connectors: params }

    assert_response :unprocessable_entity
    assert_empty Setting.disabled_connectors
  end
end
