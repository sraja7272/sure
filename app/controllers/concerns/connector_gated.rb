# Refuses the actions that start a new connection when a super admin has
# switched the connector off (Provider::ConnectorAvailability). Actions on
# existing connections -- sync, update, destroy, reauthorize, OAuth callbacks,
# account setup, and relinking an account already linked through this
# connector -- stay open so those connections keep working.
#
#   class SimplefinItemsController < ApplicationController
#     include ConnectorGated
#     gate_connector "simplefin"
#   end
module ConnectorGated
  extend ActiveSupport::Concern

  NEW_CONNECTION_ACTIONS = %w[
    new create select_accounts link_accounts select_existing_account link_existing_account
  ].freeze

  RELINK_ACTIONS = %w[select_existing_account link_existing_account].freeze

  included do
    class_attribute :gated_connector_key, instance_writer: false
  end

  class_methods do
    # @param key [String] connector key, e.g. "plaid"
    # @param also [Array<Symbol, String>] controller-specific actions that start a connection
    def gate_connector(key, also: [])
      self.gated_connector_key = key
      actions = (NEW_CONNECTION_ACTIONS + Array(also).map(&:to_s)).freeze

      before_action do
        next unless actions.include?(action_name)
        next if RELINK_ACTIONS.include?(action_name) && account_linked_through_connector?(key)

        require_connector_enabled!(key)
      end
    end
  end

  private
    # "Change <provider> account" on an account this connector already feeds
    # manages an existing connection rather than starting a new one.
    def account_linked_through_connector?(key)
      return false if params[:account_id].blank?

      account = Current.family&.accounts&.find_by(id: params[:account_id])
      return false unless account

      key = Provider::ConnectorAvailability.normalize_key(key)
      account.account_providers.pluck(:provider_type).any? do |provider_type|
        Provider::ConnectorAvailability.key_for_provider_type(provider_type) == key
      end
    end

    def require_connector_enabled!(key)
      return if Provider::ConnectorAvailability.enabled?(key)

      message = t("connectors.disabled")

      respond_to do |format|
        format.html { redirect_back_or_to accounts_path, alert: message }
        format.turbo_stream { redirect_back_or_to accounts_path, alert: message }
        format.json { render json: { error: message }, status: :forbidden }
        format.any { head :forbidden }
      end
    end
end
