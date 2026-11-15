require "test_helper"

class Admin::ConnectorsControllerTest < ActionDispatch::IntegrationTest
  setup do
    ensure_tailwind_build
    Setting.disabled_connectors = []
  end

  teardown do
    Setting.disabled_connectors = []
  end

  test "super admin sees a switch for every connector" do
    sign_in users(:sure_support_staff)

    get admin_connectors_path

    assert_response :success
    assert_select "form[data-controller='auto-submit-form']"
    Provider::ConnectorAvailability.keys.each do |key|
      assert_select "input[type=checkbox][name='connectors[#{key}]'][data-auto-submit-form-target='auto']"
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

  test "saving with every connector off is refused" do
    sign_in users(:sure_support_staff)
    params = Provider::ConnectorAvailability.keys.index_with { "0" }

    patch admin_connectors_path, params: { connectors: params }

    assert_response :unprocessable_entity
    assert_empty Setting.disabled_connectors
  end
end
