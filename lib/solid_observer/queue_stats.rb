# frozen_string_literal: true

module SolidObserver
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

    class << self
      def snapshot(range: DEFAULT_RANGE)
        new.snapshot(range)
      end

      def solid_queue_available?
        !!(defined?(SolidQueue) && defined?(SolidQueue::Job))
      end

      def parse_range(value)
        range_key = value.to_s
        RANGES.key?(range_key) ? range_key : DEFAULT_RANGE
      end

      def range_duration(value)
        RANGES.fetch(parse_range(value))
      end
    end

    def snapshot(range = DEFAULT_RANGE)
      klass = self.class
      return error_response("SolidQueue not available") unless klass.solid_queue_available?

      snapshot_for_mode(klass.parse_range(range))
    rescue => e
      error_response(e.message)
    end

    private

    def snapshot_for_mode(range_key)
      base = snapshot_base
      return base unless SolidObserver.config.persistence_mode?

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
