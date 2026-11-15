module SsoAutoRedirectable
  extend ActiveSupport::Concern

  included do
    helper_method :sso_auto_redirect_provider
  end

  private

    # The provider the sign-in and create-account pages hand off to, or nil
    # when they should render normally. Demo hosts sign in with prefilled
    # password credentials, so they never hand off.
    def sso_auto_redirect_provider
      return @sso_auto_redirect_provider if defined?(@sso_auto_redirect_provider)

      @sso_auto_redirect_provider = demo_host? ? nil : AuthConfig.auto_redirect_provider
    end

    def demo_host?
      demo = Rails.application.config_for(:demo)
      demo.present? && demo["hosts"].present? && demo["hosts"].include?(request.host)
    rescue RuntimeError, Errno::ENOENT, Psych::SyntaxError
      false
    end
end
