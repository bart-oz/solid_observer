# frozen_string_literal: true

module SolidObserver
  class Subscriber
    EVENTS = %w[
      enqueue.active_job
      perform.active_job
      retry_stopped.active_job
      discard.active_job
    ].freeze

    class << self
      def subscribe!
        return unless SolidObserver.config.observe_queue

        @subscriptions = []
        @subscriptions << subscribe_to_enqueue
        @subscriptions << subscribe_to_perform
        @subscriptions << subscribe_to_retry_stopped
        @subscriptions << subscribe_to_discard
        @subscriptions.compact!
      end

      def unsubscribe!
        return unless @subscriptions

        @subscriptions.each do |subscription|
          ActiveSupport::Notifications.unsubscribe(subscription)
        end
        @subscriptions = []
      end

      def subscribed?
        @subscriptions&.any?
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
