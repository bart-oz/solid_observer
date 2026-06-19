# frozen_string_literal: true

require_relative "storage_info_snapshot"

module SolidObserver
  module Services
    # :reek:TooManyConstants
    class CableStats
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
        broadcasts: [],
        rejections: []
      }.freeze
      STABILITY_EMPTY = {
        available: false,
        state: :stable,
        rejection_count: 0,
        error_count: 0,
        rejection_rate: 0.0,
        backlog_ratio: nil,
        backlog_available: false,
        latest_recorded_at: nil
      }.freeze
      STABILITY_DEGRADED = {
        available: true,
        state: :degraded,
        rejection_count: 0,
        error_count: 0,
        rejection_rate: 0.0,
        backlog_ratio: nil,
        backlog_available: false,
        latest_recorded_at: nil
      }.freeze
      BUCKET_RULES = [
        [2.hours.to_i, 1.minute.to_i],
        [1.day.to_i, 15.minutes.to_i],
        [7.days.to_i, 2.hours.to_i]
      ].freeze

      class TrendData
        class BucketSnapshot
          attr_reader :broadcasts_count, :rejections_count

          def initialize
            @broadcasts_count = 0
            @rejections_count = 0
          end

          def add(row)
            @broadcasts_count += row[1].to_i
            @rejections_count += row[4].to_i
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
          return CableStats::ACTIVITY_TREND_EMPTY.dup if metric_rows.empty?

          buckets = blank_buckets
          metric_rows.each do |row|
            buckets[align_bucket(row[0].to_i)]&.add(row)
          end

          {
            available: true,
            broadcasts: count_series(buckets, :broadcasts_count),
            rejections: count_series(buckets, :rejections_count)
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

        def count_series(buckets, key)
          buckets.map do |timestamp, totals|
            {t: timestamp, v: totals.value_for(key)}
          end
        end

        def bucket_seconds
          seconds = window.to_i
          CableStats::BUCKET_RULES.find { |limit, _bucket| seconds <= limit }&.last || 4.hours.to_i
        end

        def align_bucket(value)
          (value / bucket_seconds) * bucket_seconds
        end
      end

      class BacklogSnapshot
        def self.call
          new.call
        end

        # :reek:TooManyStatements
        def call
          snapshot = fetch_snapshot
          return unavailable unless snapshot && snapshot[:available]

          count = snapshot[:trimmable_count].to_i
          total = snapshot[:event_count].to_i

          {
            available: true,
            count: count,
            ratio: total.positive? ? count.to_f / total.to_f : 0.0
          }
        rescue *StorageInfoSnapshot::CONNECTION_ERRORS, TypeError, NoMethodError
          unavailable
        end

        private

        def fetch_snapshot
          StorageInfoSnapshot.call.find { |component| component[:component] == "solid_cable" }
        end

        def unavailable
          {available: false, count: nil, ratio: nil}
        end
      end

      class StabilityData
        def initialize(window:, current_time:, backlog_snapshot:)
          @window = window
          @current_time = current_time
          @backlog_snapshot = backlog_snapshot
        end

        def to_h(metric_broadcasts_count:, metric_rejections_count:)
          compute(
            metric_broadcasts_count: metric_broadcasts_count,
            metric_rejections_count: metric_rejections_count
          ).to_h
        rescue ActiveRecord::StatementInvalid
          CableStats::STABILITY_DEGRADED.dup
        end

        private

        attr_reader :window, :current_time, :backlog_snapshot

        # :reek:TooManyStatements
        def compute(metric_broadcasts_count:, metric_rejections_count:)
          event_counts = query_event_counts
          rejection_count = event_counts[:rejection_count]
          error_count = event_counts[:error_count]
          rejection_rate = CableStats.ratio(metric_rejections_count, metric_broadcasts_count)
          rejection_present = rejection_count.to_i.positive? || metric_rejections_count.to_i.positive?
          backlog_ratio = backlog_snapshot[:ratio]
          backlog_available = backlog_snapshot[:available]

          {
            available: true,
            state: stability_state(
              error_count: error_count,
              rejection_rate: rejection_rate,
              rejection_present: rejection_present,
              backlog_ratio: backlog_ratio,
              backlog_available: backlog_available
            ),
            rejection_count: rejection_count,
            error_count: error_count,
            rejection_rate: rejection_rate,
            backlog_ratio: backlog_ratio,
            backlog_available: backlog_available,
            latest_recorded_at: event_counts[:latest_recorded_at]
          }
        end

        # :reek:ControlParameter
        # :reek:LongParameterList
        # :reek:TooManyStatements
        def stability_state(error_count:, rejection_rate:, rejection_present:, backlog_ratio:, backlog_available:)
          config = SolidObserver.config

          return :critical if error_count.to_i > config.cable_error_threshold.to_i
          return :critical if rejection_rate >= config.cable_rejection_threshold.to_f
          return :critical if backlog_ratio && backlog_ratio >= 0.5
          return :degraded if backlog_ratio && backlog_ratio >= config.cable_backlog_threshold.to_f
          return :degraded if rejection_present
          return :degraded unless backlog_available

          :stable
        end

        def query_event_counts
          rejection_count, error_count, latest_recorded_at = SolidObserver::CableEvent.where(recorded_at: window_range).pick(
            Arel.sql("COUNT(CASE WHEN event_type = 'transmit_subscription_rejection' THEN 1 END)"),
            Arel.sql("COUNT(CASE WHEN error_class IS NOT NULL AND TRIM(error_class) != '' THEN 1 END)"),
            Arel.sql("MAX(CASE WHEN event_type = 'transmit_subscription_rejection' OR (error_class IS NOT NULL AND TRIM(error_class) != '') THEN recorded_at END)")
          )

          {
            rejection_count: rejection_count.to_i,
            error_count: error_count.to_i,
            latest_recorded_at: parse_latest_recorded_at(latest_recorded_at)
          }
        end

        def parse_latest_recorded_at(value)
          return nil unless value.present?

          value.is_a?(Time) ? value : Time.parse(value.to_s)
        rescue ArgumentError
          nil
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

        def ratio(numerator, denominator)
          return 0.0 if denominator.to_i.zero?

          numerator.to_f / denominator.to_f
        end
      end

      def self.call(window:)
        new.call(window: window)
      end

      def call(window:)
        current_time = Time.current
        dashboard_response(window: window, current_time: current_time)
      rescue => error
        Rails.logger&.error("[SolidObserver] CableStats call failed: #{error.class} #{error.message}") if defined?(Rails)
        error_response
      end

      private

      def dashboard_response(window:, current_time:)
        time_window = (current_time - window)..current_time
        metric_rows = metric_rows(time_window: time_window)
        totals = metric_totals(time_window: time_window)
        backlog_snapshot = BacklogSnapshot.call

        build_response(
          totals: totals,
          backlog_snapshot: backlog_snapshot,
          dashboard_data: dashboard_data(
            window: window,
            current_time: current_time,
            metric_rows: metric_rows,
            totals: totals,
            backlog_snapshot: backlog_snapshot
          )
        )
      end

      # :reek:FeatureEnvy
      # :reek:LongParameterList
      def build_response(totals:, backlog_snapshot:, dashboard_data:)
        broadcasts_count = totals[:broadcasts_count]
        rejections_count = totals[:rejections_count]

        {
          broadcasts_count: broadcasts_count,
          transmissions_count: totals[:transmissions_count],
          confirmations_count: totals[:confirmations_count],
          rejections_count: rejections_count,
          perform_actions_count: totals[:perform_actions_count],
          errors_count: totals[:errors_count],
          rejection_rate: self.class.ratio(rejections_count, broadcasts_count),
          activity_trends: dashboard_data[:activity_trends],
          stability: dashboard_data[:stability],
          backlog_count: backlog_snapshot[:count],
          backlog_available: backlog_snapshot[:available]
        }
      end

      # :reek:LongParameterList
      def dashboard_data(window:, current_time:, metric_rows:, totals:, backlog_snapshot:)
        {
          activity_trends: TrendData.new(
            metric_rows: metric_rows,
            window: window,
            current_time: current_time
          ).to_h,
          stability: StabilityData.new(
            window: window,
            current_time: current_time,
            backlog_snapshot: backlog_snapshot
          ).to_h(
            metric_broadcasts_count: totals[:broadcasts_count],
            metric_rejections_count: totals[:rejections_count]
          )
        }
      end

      def metric_rows(time_window:)
        SolidObserver::CableMetric.where(period_start: time_window).pluck(
          :period_start,
          :broadcasts_count,
          :transmissions_count,
          :confirmations_count,
          :rejections_count,
          :perform_actions_count,
          :errors_count
        )
      end

      def metric_totals(time_window:)
        broadcasts_count, transmissions_count, confirmations_count, rejections_count, perform_actions_count, errors_count = SolidObserver::CableMetric.where(
          period_start: time_window
        ).pick(
          Arel.sql("COALESCE(SUM(broadcasts_count), 0)"),
          Arel.sql("COALESCE(SUM(transmissions_count), 0)"),
          Arel.sql("COALESCE(SUM(confirmations_count), 0)"),
          Arel.sql("COALESCE(SUM(rejections_count), 0)"),
          Arel.sql("COALESCE(SUM(perform_actions_count), 0)"),
          Arel.sql("COALESCE(SUM(errors_count), 0)")
        )

        {
          broadcasts_count: broadcasts_count,
          transmissions_count: transmissions_count,
          confirmations_count: confirmations_count,
          rejections_count: rejections_count,
          perform_actions_count: perform_actions_count,
          errors_count: errors_count
        }
      end

      def error_response
        {
          broadcasts_count: 0,
          transmissions_count: 0,
          confirmations_count: 0,
          rejections_count: 0,
          perform_actions_count: 0,
          errors_count: 0,
          rejection_rate: 0.0,
          activity_trends: ACTIVITY_TREND_EMPTY.dup,
          stability: STABILITY_EMPTY.dup,
          backlog_count: nil,
          backlog_available: false,
          error: "Service temporarily unavailable"
        }
      end
    end
  end
end
