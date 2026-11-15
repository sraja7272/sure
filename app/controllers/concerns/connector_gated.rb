# Refuses the actions that start a new connection when a super admin has
# switched the connector off (Provider::ConnectorAvailability). Actions on
# existing connections -- sync, update, destroy, reauthorize, OAuth callbacks,
# account setup -- stay open so those connections keep working.
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

  class_methods do
    # @param key [String] connector key, e.g. "plaid"
    # @param also [Array<Symbol, String>] controller-specific actions that start a connection
    def gate_connector(key, also: [])
      actions = (NEW_CONNECTION_ACTIONS + Array(also).map(&:to_s)).freeze

      before_action do
        require_connector_enabled!(key) if actions.include?(action_name)
      end
    end
  end

  private
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
