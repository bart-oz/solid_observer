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
      ACTIVITY_TREND_EMPTY = {
        available: false,
        hit_rate: [],
        operations: [],
        errors: []
      }.freeze
      STABILITY_EMPTY = {
        available: false,
        state: :stable,
        error_count: 0,
        slow_count: 0,
        latest_recorded_at: nil
      }.freeze
      BUCKET_RULES = [
        [2.hours.to_i, 1.minute.to_i],
        [1.day.to_i, 15.minutes.to_i],
        [7.days.to_i, 2.hours.to_i]
      ].freeze

      class TrendData
        class BucketSnapshot
          attr_reader :operations_count, :hits_count, :misses_count, :errors_count

          def initialize
            @operations_count = 0
            @hits_count = 0
            @misses_count = 0
            @errors_count = 0
          end

          def add(row)
            @operations_count += row[1].to_i
            @hits_count += row[2].to_i
            @misses_count += row[3].to_i
            @errors_count += row[4].to_i
          end

          def hit_rate
            read_outcomes = hits_count + misses_count
            return 0.0 if read_outcomes.zero?

            hits_count.to_f / read_outcomes
          end

          def value_for(key)
            public_send(key)
          end
        end

        def initialize(metric_rows:, window:, current_time:)
          @metric_rows = metric_rows
          @window = window
          @current_time = current_time
        end

        def to_h
          return CacheStats::ACTIVITY_TREND_EMPTY.dup if metric_rows.empty?

          buckets = blank_buckets
          metric_rows.each do |row|
            buckets[align_bucket(row[0].to_i)]&.add(row)
          end

          {
            available: true,
            hit_rate: hit_rate_series(buckets),
            operations: count_series(buckets, :operations_count),
            errors: count_series(buckets, :errors_count)
          }
        end

        private

        attr_reader :metric_rows, :window, :current_time

        def blank_buckets
          start_bucket = align_bucket((current_time - window).to_i)
          end_bucket = align_bucket(current_time.to_i)

          start_bucket.step(end_bucket, bucket_seconds).each_with_object({}) do |timestamp, buckets|
            buckets[timestamp] = BucketSnapshot.new
          end
        end

        def hit_rate_series(buckets)
          buckets.map do |timestamp, totals|
            {t: timestamp, v: totals.hit_rate}
          end
        end

        def count_series(buckets, key)
          buckets.map do |timestamp, totals|
            {t: timestamp, v: totals.value_for(key)}
          end
        end

        def bucket_seconds
          seconds = window.to_i
          CacheStats::BUCKET_RULES.find { |limit, _bucket| seconds <= limit }&.last || 4.hours.to_i
        end

        def align_bucket(value)
          (value / bucket_seconds) * bucket_seconds
        end
      end

      class StabilityData
        class EventCounts
          attr_reader :error_count, :slow_count, :latest_recorded_at

          def initialize
            @error_count = 0
            @slow_count = 0
            @latest_recorded_at = nil
          end

          def record(recorded_at:, error_class:, duration:)
            kind = event_kind(error_class: error_class, duration: duration)
            return unless kind

            @latest_recorded_at = [latest_recorded_at, recorded_at].compact.max
            @error_count += 1 if kind == :error
            @slow_count += 1 if kind == :slow
          end

          def state
            return :critical if error_count.positive?
            return :degraded if slow_count.positive?

            :stable
          end

          def to_h
            {
              available: true,
              state: state,
              error_count: error_count,
              slow_count: slow_count,
              latest_recorded_at: latest_recorded_at
            }
          end

          private

          def event_kind(error_class:, duration:)
            return :error if error_class.present?
            return :slow if duration.to_f >= SolidObserver.config.cache_slow_threshold.to_f

            nil
          end
        end

        def initialize(window:, current_time:)
          @window = window
          @current_time = current_time
        end

        def to_h
          event_counts.to_h
        rescue ActiveRecord::StatementInvalid
          CacheStats::STABILITY_EMPTY.dup
        end

        private

        attr_reader :window, :current_time

        def event_counts
          counts = EventCounts.new

          SolidObserver::CacheEvent.where(recorded_at: window_range).pluck(
            :recorded_at,
            :duration,
            :error_class
          ).each do |recorded_at, duration, error_class|
            counts.record(recorded_at: recorded_at, error_class: error_class, duration: duration)
          end

          counts
        end

        def window_range
          (current_time - window)..current_time
        end
      end

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
        current_time = Time.current
        dashboard_response(window: window, current_time: current_time)
      rescue => error
        error_response(error.message)
      end

      private

      def dashboard_response(window:, current_time:)
        time_window = (current_time - window)..current_time
        metric_rows = metric_rows(time_window: time_window)

        build_response(
          window: window,
          totals: metric_totals(time_window: time_window),
          dashboard_data: dashboard_data(window: window, current_time: current_time, metric_rows: metric_rows)
        )
      end

      def build_response(window:, totals:, dashboard_data:)
        operations_count, hits_count, misses_count, errors_count, duration_total = totals.values_at(
          :operations_count,
          :hits_count,
          :misses_count,
          :errors_count,
          :duration_total
        )
        read_outcomes_count = hits_count + misses_count
        window_minutes = [window.to_f / 60.0, 1.0].max

        {
          hit_rate: ratio(hits_count, read_outcomes_count),
          throughput: operations_count.to_f / window_minutes,
          error_rate: ratio(errors_count, operations_count),
          avg_duration: ratio(duration_total, operations_count),
          operations_count: operations_count,
          hits_count: hits_count,
          misses_count: misses_count,
          errors_count: errors_count,
          duration_total: duration_total,
          activity_trends: dashboard_data[:activity_trends],
          stability: dashboard_data[:stability]
        }
      end

      def dashboard_data(window:, current_time:, metric_rows:)
        {
          activity_trends: TrendData.new(
            metric_rows: metric_rows,
            window: window,
            current_time: current_time
          ).to_h,
          stability: StabilityData.new(window: window, current_time: current_time).to_h
        }
      end

      def metric_rows(time_window:)
        SolidObserver::CacheMetric.where(period_start: time_window).pluck(
          :period_start,
          :operations_count,
          :hits_count,
          :misses_count,
          :errors_count,
          :duration_total
        )
      end

      def metric_totals(time_window:)
        operations_count, hits_count, misses_count, errors_count, duration_total = SolidObserver::CacheMetric.where(
          period_start: time_window
        ).pick(
          Arel.sql("COALESCE(SUM(operations_count), 0)"),
          Arel.sql("COALESCE(SUM(hits_count), 0)"),
          Arel.sql("COALESCE(SUM(misses_count), 0)"),
          Arel.sql("COALESCE(SUM(errors_count), 0)"),
          Arel.sql("COALESCE(SUM(duration_total), 0.0)")
        )

        {
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
          activity_trends: ACTIVITY_TREND_EMPTY.dup,
          stability: STABILITY_EMPTY.dup,
          error: message
        }
      end
    end
  end
end
