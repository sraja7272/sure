require "test_helper"
require "ostruct"

class Family::PlaidConnectableTest < ActiveSupport::TestCase
  setup do
    @family = families(:dylan_family)
    @provider = mock
    Provider::Registry.stubs(:plaid_provider_for_region).with(:us).returns(@provider)
  end

  test "create_plaid_item! persists the institution id it is given" do
    stub_exchange

    item = @family.create_plaid_item!(
      public_token: "public-sandbox-1234",
      item_name: "Example Bank",
      region: :us,
      institution_id: "ins_example"
    )

    assert_equal "ins_example", item.institution_id
  end

  # institution_id is optional because this is a public model API and the column was
  # only ever populated during the first sync, by upsert_plaid_institution_snapshot!.
  # A caller that does not have the Link metadata must still be able to create an item.
  test "create_plaid_item! works without an institution id" do
    stub_exchange

    item = @family.create_plaid_item!(
      public_token: "public-sandbox-1234",
      item_name: "Example Bank",
      region: :us
    )

    assert_nil item.institution_id
    assert_equal "Example Bank", item.name
  end

  test "create_plaid_item! records the new item's usage for the month" do
    stub_exchange
    Current.stubs(:user).returns(users(:family_member))

    item = @family.create_plaid_item!(public_token: "public-sandbox-1234", item_name: "Example Bank", region: :us)

    usage = PlaidItemUsage.find_by!(plaid_item_id: item.id, period: PlaidItemUsage.current_period)
    assert_equal @family, usage.family
    assert_equal users(:family_member), usage.user
    assert_equal "Example Bank", usage.institution_name
  end

  test "create_plaid_item! still creates the item when recording usage fails" do
    stub_exchange
    PlaidItemUsage.stubs(:record!).raises(ActiveRecord::StatementInvalid, "boom")

    item = nil
    assert_difference "DebugLogEntry.count", 1 do
      item = @family.create_plaid_item!(public_token: "public-sandbox-1234", item_name: "Example Bank", region: :us)
    end

    assert item.persisted?
  end

  private
    def stub_exchange
      @provider.expects(:exchange_public_token).returns(
        OpenStruct.new(access_token: "access-sandbox-1234", item_id: "item-sandbox-#{SecureRandom.hex(4)}")
      )
    end
end
