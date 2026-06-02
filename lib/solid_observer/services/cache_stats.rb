# frozen_string_literal: true

module SolidObserver
  module Services
    class CacheStats
      RANGES = {
        "15m" => 15.minutes,
        "30m" => 30.minutes,
        "1h" => 1.hour,
        "7h" => 7.hours,
        "1d" => 1.day,
        "7d" => 7.days,
        "14d" => 14.days
      }.freeze
      DEFAULT_RANGE = "15m"

      class << self
        def parse_range(value, fallback: DEFAULT_RANGE)
          range_key = value.to_s
          RANGES.key?(range_key) ? range_key : fallback
        end

        def range_duration(value, fallback: DEFAULT_RANGE)
          RANGES.fetch(parse_range(value, fallback: fallback))
        end
      end

      def self.call(window:)
        new.call(window: window)
      end

      def call(window:)
        scope = SolidObserver::CacheMetric.where(period_start: window_start(window)..Time.current)
        totals = scope.pick(
          Arel.sql("COALESCE(SUM(operations_count), 0)"),
          Arel.sql("COALESCE(SUM(hits_count), 0)"),
          Arel.sql("COALESCE(SUM(misses_count), 0)"),
          Arel.sql("COALESCE(SUM(errors_count), 0)"),
          Arel.sql("COALESCE(SUM(duration_total), 0.0)")
        )

        build_response(window: window, totals: totals)
      rescue => error
        error_response(error.message)
      end

      private

      def build_response(window:, totals:)
        operations_count, hits_count, misses_count, errors_count, duration_total = totals
        window_minutes = [window.to_f / 60.0, 1.0].max

        read_outcomes_count = hits_count.to_i + misses_count.to_i

        {
          hit_rate: ratio(hits_count, read_outcomes_count),
          throughput: operations_count.to_f / window_minutes,
          error_rate: ratio(errors_count, operations_count),
          avg_duration: ratio(duration_total, operations_count),
          operations_count: operations_count,
          hits_count: hits_count,
          misses_count: misses_count,
          errors_count: errors_count,
          duration_total: duration_total
        }
      end

      def ratio(numerator, denominator)
        return 0.0 if denominator.to_i.zero?

        numerator.to_f / denominator
      end

      def window_start(window)
        Time.current - window
      end

      def error_response(message)
        {
          hit_rate: 0.0,
          throughput: 0.0,
          error_rate: 0.0,
          avg_duration: 0.0,
          operations_count: 0,
          hits_count: 0,
          misses_count: 0,
          errors_count: 0,
          duration_total: 0.0,
          error: message
        }
      end
    end
  end
end
