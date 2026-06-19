# frozen_string_literal: true

module SolidObserver
  class CableSubscriber
    EVENTS = %w[
      broadcast.action_cable
      transmit.action_cable
      transmit_subscription_confirmation.action_cable
      transmit_subscription_rejection.action_cable
      perform_action.action_cable
    ].freeze

    class << self
      attr_reader :subscriptions

      def subscribe
        return unless subscription_allowed?

        self.subscriptions = EVENTS.map { |event_name| subscribe_to(event_name) }
      end

      def unsubscribe
        return unless subscriptions

        subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
        self.subscriptions = []
      end

      def subscribe!
        subscribe
      end

      def unsubscribe!
        unsubscribe
      end

      def subscribed?
        !!subscriptions&.any?
      end

      private

      attr_writer :subscriptions

      def subscription_allowed?
        SolidObserver.config.solid_cable_enabled? && !subscribed? && defined?(ActiveSupport::Notifications)
      end

      def subscribe_to(event_name)
        ActiveSupport::Notifications.subscribe(event_name) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordCableEvent.call(event: event, buffer: CableEventBuffer.instance)
        end
      end
    end
  end
end
