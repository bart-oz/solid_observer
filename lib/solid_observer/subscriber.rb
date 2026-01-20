# frozen_string_literal: true

module SolidObserver
  class Subscriber
    class << self
      def subscribe!
        return unless SolidObserver.config.observe_queue

        subscribe_to_enqueue
        subscribe_to_perform
        subscribe_to_retry_stopped
        subscribe_to_discard
      end

      private

      def subscribe_to_enqueue
        ActiveSupport::Notifications.subscribe("enqueue.active_job") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordEvent.call(
            event: event,
            event_type: "job_enqueued",
            buffer: QueueEventBuffer.instance,
            metric_name: "jobs_enqueued"
          )
        end
      end

      def subscribe_to_perform
        ActiveSupport::Notifications.subscribe("perform.active_job") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordEvent.call(
            event: event,
            event_type: "job_completed",
            buffer: QueueEventBuffer.instance,
            metric_name: "jobs_completed"
          )
        end
      end

      def subscribe_to_retry_stopped
        ActiveSupport::Notifications.subscribe("retry_stopped.active_job") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordEvent.call(
            event: event,
            event_type: "job_failed",
            buffer: QueueEventBuffer.instance,
            metric_name: "jobs_failed"
          )
        end
      end

      def subscribe_to_discard
        ActiveSupport::Notifications.subscribe("discard.active_job") do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordEvent.call(
            event: event,
            event_type: "job_discarded",
            buffer: QueueEventBuffer.instance,
            metric_name: "jobs_discarded"
          )
        end
      end
    end
  end
end
