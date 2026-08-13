# frozen_string_literal: true

# Not redundant with Zeitwerk: spec_helper.rb requires app/controllers/**/*.rb in
# glob order, and "alerts_controller" sorts before "application_controller".
# Same reason cache_dashboard_controller.rb requires dashboard_controller.
require_relative "application_controller"

module SolidObserver
  class AlertsController < ApplicationController
    include RequirePersistenceMode

    def index
      @rules = AlertRule.order(:rule_name)
      @active = AlertHistory.active.order(triggered_at: :desc)
      @recent = AlertHistory.recent
    end

    def show
      @rule = AlertRule.find_by(id: params[:id])
      return redirect_to(alerts_path, alert: "Alert rule not found") unless @rule

      @histories = @rule.alert_histories.recent
    end
  end
end
