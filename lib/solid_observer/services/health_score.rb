# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module SolidObserver
  module Services
    class HealthScore
      STATUS_RANK = {stable: 0, degraded: 1, critical: 2}.freeze
      UNAVAILABLE = {status: :degraded, available: false}.freeze
      WINDOW = 15.minutes

      def self.call
        new.call
      end

      def call
        components = collect_components
        {
          overall: overall_status(components.values.map { |entry| entry[:status] }),
          components: components
        }
      end

      private

      # :reek:FeatureEnvy
      # :reek:TooManyStatements
      def collect_components
        config = SolidObserver.config
        components = {}

        components[:queue] = queue_component if config.solid_queue_enabled?

        unless config.realtime_mode?
          components[:cache] = stats_component(:cache, CacheStats) if config.solid_cache_enabled?
          components[:cable] = stats_component(:cable, CableStats) if config.solid_cable_enabled?
        end

        components
      end

      def queue_component
        snapshot = SolidObserver::QueueStats.snapshot
        return UNAVAILABLE.dup unless snapshot[:available]

        {status: queue_stability(snapshot), available: true}
      rescue => error
        degrade(:queue, error)
      end

      def queue_stability(snapshot)
        return :critical if snapshot[:failed_last_hour].to_i.positive?
        return :degraded if snapshot[:failed_last_24h].to_i.positive?

        :stable
      end

      def stats_component(name, stats_class)
        stability = stats_class.call(window: WINDOW)[:stability]
        return UNAVAILABLE.dup unless stability&.[](:available)

        {status: stability[:state] || :degraded, available: true}
      rescue => error
        degrade(name, error)
      end

      def overall_status(statuses)
        return :stable if statuses.empty?

        statuses.max_by { |status| STATUS_RANK.fetch(status, 1) }
      end

      def degrade(name, error)
        log_component_error(name, error)
        UNAVAILABLE.dup
      end

      def log_component_error(name, error)
        return unless defined?(Rails)

        Rails.logger&.warn("HealthScore #{name} error: #{error.message}")
      end
    end
  end
end
