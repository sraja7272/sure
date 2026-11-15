require "test_helper"

class AuthConfigTest < ActiveSupport::TestCase
  OIDC = { id: "oidc", strategy: "openid_connect", name: "openid_connect" }.freeze
  GOOGLE = { id: "google", strategy: "google_oauth2", name: "google_oauth2" }.freeze

  test "auto_redirect_provider is nil when the flag is off" do
    stub_auth(auto_redirect: false, providers: [ OIDC ])

    assert_nil AuthConfig.auto_redirect_provider
  end

  test "auto_redirect_provider returns the only registered provider when the flag is on" do
    stub_auth(auto_redirect: true, providers: [ OIDC ])

    assert_equal OIDC, AuthConfig.auto_redirect_provider
  end

  test "auto_redirect_provider is nil with several registered providers" do
    stub_auth(auto_redirect: true, providers: [ OIDC, GOOGLE ])

    assert_nil AuthConfig.auto_redirect_provider
  end

  test "auto_redirect_provider is nil with no registered provider" do
    stub_auth(auto_redirect: true, providers: [])

    assert_nil AuthConfig.auto_redirect_provider
  end

  private

    def stub_auth(auto_redirect:, providers:)
      Rails.configuration.x.auth.stubs(:sso_auto_redirect).returns(auto_redirect)
      Rails.configuration.x.auth.stubs(:sso_providers).returns(providers)
    end
end
