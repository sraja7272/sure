class Settings::UsageCostsController < ApplicationController
  layout "settings"

  # Always the signed-in person's own figures; no param selects anyone else.
  def show
    @report = UsageCostReport.new(month: params[:month], family: Current.family, user: Current.user)
  end
end
