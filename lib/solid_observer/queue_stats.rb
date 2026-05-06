# frozen_string_literal: true

module SolidObserver
  class QueueStats
    class << self
      def snapshot
        new.snapshot
      end

      def solid_queue_available?
        !!(defined?(SolidQueue) && defined?(SolidQueue::Job))
      end
    end

    def snapshot
      return unavailable_response unless self.class.solid_queue_available?

      snapshot_for_mode
    rescue => e
      error_response(e)
    end

    private

    def snapshot_for_mode
      base = snapshot_base
      return base unless SolidObserver.config.persistence_mode?

      base.merge(throughput_stats)
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

    def throughput_stats
      one_hour = 1.hour
      {
        performed_last_hour: QueueEvent.performed_count_last(one_hour),
        failed_last_24h: QueueEvent.failed_count_last(24.hours),
        failed_last_hour: QueueEvent.failed_count_last(one_hour),
        latest_failure_at: QueueEvent.recent_failures(1).first&.recorded_at,
        enqueue_rate_per_min: QueueEvent.enqueue_rate_per_minute(window: 5.minutes)
      }
    end

    def unavailable_response
      {
        ready: 0,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 0,
        queues: {},
        available: false,
        error: "SolidQueue not available"
      }
    end

    def error_response(exception)
      {
        ready: 0,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 0,
        queues: {},
        available: false,
        error: exception.message
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
