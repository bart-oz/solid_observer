# frozen_string_literal: true

require_relative "dashboard_controller"

module SolidObserver
  # :reek:TooManyInstanceVariables
  class CableDashboardController < DashboardController
    CABLE_STORAGE_COMPONENTS = %w[cable_observer solid_cable].freeze

    def index
      @component = "cable"
      assign_cable_dashboard
    end

    private

    # :reek:TooManyStatements
    def assign_cable_dashboard
      unless SolidObserver.config.solid_cable_enabled?
        @cable_dashboard_available = false
        @storage_components = []
        @recent_events = []
        return
      end

      range = SolidObserver::Services::CableStats.parse_range(request_range_param)
      window = SolidObserver::Services::CableStats.range_duration(range)
      stats = SolidObserver::Services::CableStats.call(window: window)

      @cable_dashboard_available = true
      @range = range
      @stats = stats
      @storage_components = cable_storage_components
      @recent_events = recent_events(window)
    end

    def cable_storage_components
      SolidObserver::Services::StorageInfoSnapshot.call.select do |snapshot|
        CABLE_STORAGE_COMPONENTS.include?(snapshot[:component])
      end
    rescue *SolidObserver::Services::StorageInfoSnapshot::CONNECTION_ERRORS, TypeError, NoMethodError
      []
    end

    def recent_events(window)
      current_time = Time.current
      SolidObserver::CableEvent.where(recorded_at: (current_time - window)..current_time).recent(10)
    rescue ActiveRecord::StatementInvalid
      []
    end
  end
end
