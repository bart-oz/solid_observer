# frozen_string_literal: true

module SolidObserver
  module Services
    class RecordCacheMetric
      def self.call(event:)
        new(event).call
      end

      def initialize(event)
        @event = event
      end

      def call
        metric = SolidObserver::CacheMetric.find_or_create_by!(
          event_type: event_type,
          period_start: period_start
        )

        SolidObserver::CacheMetric
          .where(id: metric.id)
          .update_all(update_values)
      rescue ActiveRecord::RecordNotUnique
        retry
      rescue => error
        Rails.logger&.warn("[SolidObserver] Cache metric recording failed: #{error.message}") if defined?(Rails)
      end

      private

      def period_start
        Time.current.beginning_of_minute
      end

      def event_type
        @event.name.delete_suffix(".active_support")
      end

      def update_values
        {
          operations_count: Arel.sql("operations_count + 1"),
          hits_count: Arel.sql("hits_count + #{hit_increment}"),
          misses_count: Arel.sql("misses_count + #{miss_increment}"),
          errors_count: Arel.sql("errors_count + #{error_increment}"),
          duration_total: Arel.sql("duration_total + #{duration_in_seconds}")
        }
      end

      def hit_increment
        (payload[:hit] == true) ? 1 : 0
      end

      def miss_increment
        (payload[:hit] == false) ? 1 : 0
      end

      def error_increment
        exception_present? ? 1 : 0
      end

      def exception_present?
        payload[:exception_object].present? || payload[:exception].is_a?(Array)
      end

      def duration_in_seconds
        (@event.duration || 0).to_f / 1000.0
      end

      def payload
        @event.payload || {}
      end
    end
  end
end
