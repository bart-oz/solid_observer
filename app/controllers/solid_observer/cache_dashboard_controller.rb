# frozen_string_literal: true

require_relative "dashboard_controller"

module SolidObserver
  class CacheDashboardController < DashboardController
    CACHE_STORAGE_COMPONENTS = %w[solid_cache cache_observer].freeze

    class << self
      def cache_dashboard_assignments(range_param:)
        return unavailable_assignments unless SolidObserver.config.solid_cache_enabled?

        range = SolidObserver::Services::CacheStats.parse_range(range_param)
        window = SolidObserver::Services::CacheStats.range_duration(range)
        stats = SolidObserver::Services::CacheStats.call(window: window)

        {
          cache_dashboard_available: true,
          range: range,
          stats: stats,
          activity_trends: stats[:activity_trends],
          stability: stats[:stability],
          storage_components: cache_storage_components,
          recent_events: recent_events(window)
        }
      end

      private

      def unavailable_assignments
        {
          cache_dashboard_available: false,
          storage_components: [],
          recent_events: [],
          activity_trends: SolidObserver::Services::CacheStats::ACTIVITY_TREND_EMPTY,
          stability: SolidObserver::Services::CacheStats::STABILITY_EMPTY
        }
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

    def index
      @component = "cache"
      assign_cache_dashboard
    end
  end
end
