# frozen_string_literal: true

module SolidObserver
  # Subscribes to ActiveSupport::Notifications for ActiveJob events.
  #
  # Monitors job lifecycle events (enqueue, perform, retry_stopped, discard)
  # and records them through the event buffer for observability.
  #
  # @example Subscribe to job events
  #   SolidObserver::Subscriber.subscribe!
  class Subscriber
    EVENTS = %w[
      enqueue.active_job
      perform.active_job
      retry_stopped.active_job
      discard.active_job
    ].freeze

    class << self
      def subscribe!
        return unless subscription_allowed?

        @subscriptions = subscriptions_for_events.compact
      end

      def unsubscribe!
        return unless @subscriptions

        @subscriptions.each do |subscription|
          ActiveSupport::Notifications.unsubscribe(subscription)
        end
        @subscriptions = []
      end

      def subscribed?
        !!@subscriptions&.any?
      end

      private

      def subscription_allowed?
        SolidObserver.config.observe_queue && !subscribed?
      end

      def subscriptions_for_events
        [
          subscribe_to_enqueue,
          subscribe_to_perform,
          subscribe_to_retry_stopped,
          subscribe_to_discard
        ]
      end

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
