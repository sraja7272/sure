# frozen_string_literal: true

module Admin
  class UsageCostsController < Admin::BaseController
    def show
      @breadcrumbs = [
        [ t("breadcrumbs.home"), root_path ],
        [ t("breadcrumbs.usage_cost_report"), nil ]
      ]
      @report = UsageCostReport.new(month: params[:month])
      @rates = PlaidItemUsage.rates

      respond_to do |format|
        format.html
        format.csv do
          send_data @report.to_csv, filename: "usage-costs-#{@report.period}.csv", type: "text/csv"
        end
      end
    end

    def update
      period = UsageCostReport.new(month: params[:month]).period

      if PlaidItemUsage.update_rates(rate_params.to_h)
        redirect_to admin_usage_costs_path(month: period), notice: t(".success")
      else
        redirect_to admin_usage_costs_path(month: period), alert: t(".invalid")
      end
    end

    private
      def rate_params
        params.permit(plaid_rates: PlaidItemUsage::RATE_SETTINGS.keys).fetch(:plaid_rates, {})
      end
  end
end
