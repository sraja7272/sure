# frozen_string_literal: true

module Admin
  class ConnectorsController < Admin::BaseController
    def show
      set_page
    end

    # The page saves batched switch changes in the background and keeps its own
    # switch state, so a successful save answers with nothing: redrawing the
    # switches could undo clicks made while the save was in flight.
    def update
      Provider::ConnectorAvailability.update!(
        enabled_keys_param, client_id: params[:client_id], sequence: params[:sequence]
      )

      respond_to do |format|
        format.turbo_stream { head :no_content }
        format.html { redirect_to admin_connectors_path, notice: t(".success") }
      end
    rescue Provider::ConnectorAvailability::NoneEnabledError
      set_page
      respond_to do |format|
        format.turbo_stream do
          flash.now[:alert] = t(".none_enabled")
          render turbo_stream: [
            turbo_stream.replace("connector_switches", partial: "admin/connectors/switches"),
            *flash_notification_stream_items
          ], status: :unprocessable_entity
        end
        format.html do
          flash.now[:alert] = t(".none_enabled")
          render :show, status: :unprocessable_entity
        end
      end
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
