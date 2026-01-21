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

      {
        ready: ready_count,
        scheduled: scheduled_count,
        claimed: claimed_count,
        failed: failed_count,
        workers: active_workers_count,
        queues: queue_depths,
        available: true
      }
    rescue => e
      error_response(e)
    end

    private

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
