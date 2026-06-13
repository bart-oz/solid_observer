# frozen_string_literal: true

require_relative "dashboard_controller"

module SolidObserver
  class CacheDashboardController < DashboardController
    CACHE_STORAGE_COMPONENTS = %w[solid_cache cache_observer].freeze

    def index
      @component = "cache"
      assign_cache_dashboard
    end

    private

    def assign_cache_dashboard
      unless SolidObserver.config.solid_cache_enabled?
        @cache_dashboard_available = false
        @storage_components = []
        @recent_events = []
        @activity_trends = SolidObserver::Services::CacheStats::ACTIVITY_TREND_EMPTY
        @stability = SolidObserver::Services::CacheStats::STABILITY_EMPTY
        return
      end

      range = SolidObserver::Services::CacheStats.parse_range(request_range_param)
      window = SolidObserver::Services::CacheStats.range_duration(range)
      stats = SolidObserver::Services::CacheStats.call(window: window)

      @cache_dashboard_available = true
      @range = range
      @stats = stats
      @activity_trends = stats[:activity_trends]
      @stability = stats[:stability]
      @storage_components = cache_storage_components
      @recent_events = recent_events(window)
    end

    def cache_storage_components
      SolidObserver::Services::StorageInfoSnapshot.call.select do |snapshot|
        CACHE_STORAGE_COMPONENTS.include?(snapshot[:component])
      end
    end

    def recent_events(window)
      current_time = Time.current
      SolidObserver::CacheEvent.where(recorded_at: (current_time - window)..current_time).recent(10)
    rescue ActiveRecord::StatementInvalid
      []
    end
  end
end
