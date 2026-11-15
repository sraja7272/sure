# frozen_string_literal: true

module Admin
  class ConnectorsController < Admin::BaseController
    def show
      set_page
    end

    def update
      Provider::ConnectorAvailability.update!(enabled_keys_param)
      redirect_to admin_connectors_path, notice: t(".success")
    rescue Provider::ConnectorAvailability::NoneEnabledError
      set_page
      flash.now[:alert] = t(".none_enabled")
      render :show, status: :unprocessable_entity
    rescue Provider::ConnectorAvailability::UnknownConnectorError
      redirect_to admin_connectors_path, alert: t(".unknown_connector")
    end

    private
      # The form posts connectors[<key>] = "1" (on) or "0" (off) for every connector.
      def enabled_keys_param
        params.fetch(:connectors, {})
          .permit(*Provider::ConnectorAvailability.keys)
          .to_h
          .select { |_key, value| value == "1" }
          .keys
      end

      def set_page
        @breadcrumbs = [
          [ t("breadcrumbs.home"), root_path ],
          [ t("admin.connectors.show.page_title"), nil ]
        ]
        @connectors_by_kind = Provider::ConnectorAvailability.all.group_by(&:kind)
        @enabled_keys = Provider::ConnectorAvailability.enabled_keys.to_set
      end
  end
end
