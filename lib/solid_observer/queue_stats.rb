# frozen_string_literal: true

require_relative "chart_buffer"

module SolidObserver
  # :reek:TooManyMethods
  class QueueStats
    RANGES = {
      "15m" => 15.minutes,
      "30m" => 30.minutes,
      "1h" => 1.hour,
      "7h" => 7.hours,
      "1d" => 1.day,
      "7d" => 7.days,
      "14d" => 14.days
    }.freeze
    DEFAULT_RANGE = "1h"
    POLL_DEFAULT_RANGE = "15m"
    POLL_EMPTY_SNAPSHOT = {
      ready: 0,
      scheduled: 0,
      claimed: 0,
      workers: 0,
      failed: 0,
      enqueue_rate_per_min: nil
    }.freeze
    BUCKET_RULES = [
      [30.minutes.to_i, 30],
      [2.hours.to_i, 60],
      [1.day.to_i, 5.minutes.to_i]
    ].freeze

    class << self
      def snapshot(range: DEFAULT_RANGE)
        new.snapshot(range)
      end

      def snapshot_for_poll(range:)
        new.snapshot_for_poll(parse_range(range, fallback: POLL_DEFAULT_RANGE))
      end

      def chart_data(window: 15.minutes)
        new.chart_data(window)
      end

      def solid_queue_available?
        !!(defined?(SolidQueue) && defined?(SolidQueue::Job))
      end

      def parse_range(value, fallback: DEFAULT_RANGE)
        range_key = value.to_s
        RANGES.key?(range_key) ? range_key : fallback
      end

      def range_duration(value, fallback: DEFAULT_RANGE)
        RANGES.fetch(parse_range(value, fallback: fallback))
      end
    end

    def snapshot(range = DEFAULT_RANGE)
      klass = self.class
      return snapshot_for_mode(range && klass.parse_range(range)) if klass.solid_queue_available?

      error_response("SolidQueue not available")
    rescue => e
      error_response(e.message)
    end

    # :reek:TooManyStatements
    def snapshot_for_poll(range)
      empty_snapshot = POLL_EMPTY_SNAPSHOT.dup
      klass = self.class
      return empty_snapshot unless klass.solid_queue_available?

      window = klass.range_duration(range, fallback: POLL_DEFAULT_RANGE)
      {
        ready: ready_count,
        scheduled: scheduled_count,
        claimed: claimed_count,
        workers: active_workers_count,
        failed: failed_count,
        enqueue_rate_per_min: SolidObserver.config.persistence_mode? ? QueueEvent.enqueue_rate_per_minute(window: window) : nil
      }
    rescue
      empty_snapshot
    end

    # :reek:TooManyStatements
    def chart_data(window)
      seconds = window.to_i
      ready = ChartBuffer.recent(seconds)
      return {performed: [], failed: [], ready: ready} unless SolidObserver.config.persistence_mode?

      bucket_seconds = derive_bucket_seconds(window)
      {
        performed: QueueEvent.count_by_time_bucket(
          event_type: "job_completed",
          window: window,
          bucket_seconds: bucket_seconds
        ),
        failed: QueueEvent.count_by_time_bucket(
          event_type: "job_failed",
          window: window,
          bucket_seconds: bucket_seconds
        ),
        ready: ready
      }
    end

    private

    def derive_bucket_seconds(window)
      seconds = window.to_i
      BUCKET_RULES.find { |limit, _bucket| seconds <= limit }&.last || 30.minutes.to_i
    end

    def snapshot_for_mode(range_key)
      base = snapshot_base
      return base unless SolidObserver.config.persistence_mode? && range_key

      base.merge(throughput_stats(range_key)).merge(range: range_key)
    end

    def snapshot_base
      {
        ready: ready_count,
        scheduled: scheduled_count,
        claimed: claimed_count,
        failed: failed_count,
        workers: active_workers_count,
        queues: queue_depths,
        available: true
      }
    end

    def throughput_stats(range_key)
      duration = self.class.range_duration(range_key)
      {
        performed_in_range: QueueEvent.performed_count_last(duration),
        failed_in_range: QueueEvent.failed_count_last(duration),
        # Stability indicator still uses dedicated rolling windows independent of selected range.
        failed_last_24h: QueueEvent.failed_count_last(24.hours),
        failed_last_hour: QueueEvent.failed_count_last(1.hour),
        latest_failure_at: QueueEvent.recent_failures(1).first&.recorded_at,
        enqueue_rate_per_min: QueueEvent.enqueue_rate_per_minute(window: duration)
      }
    end

    def error_response(message)
      {
        ready: 0,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 0,
        queues: {},
        available: false,
        range: DEFAULT_RANGE,
        error: message
      }
    end

    def ready_count
      SolidQueue::ReadyExecution.count
    end

    def scheduled_count
      SolidQueue::ScheduledExecution.count
    end

    def claimed_count
      SolidQueue::ClaimedExecution.count
    end

    def failed_count
      SolidQueue::FailedExecution.count
    end

    def active_workers_count
      return 0 unless defined?(SolidQueue::Process)

      SolidQueue::Process.where(kind: "Worker").count
    end

    def queue_depths
      return {} unless defined?(SolidQueue::ReadyExecution)

      SolidQueue::ReadyExecution
        .group(:queue_name)
        .count
    end
  end
end
