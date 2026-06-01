# frozen_string_literal: true

module SolidObserver
  class CacheSubscriber
    EVENTS = %w[
      cache_read.active_support
      cache_write.active_support
      cache_delete.active_support
      cache_exist?.active_support
      cache_read_multi.active_support
      cache_write_multi.active_support
      cache_delete_multi.active_support
    ].freeze

    class << self
      def subscribe!
        return unless subscription_allowed?

        @subscriptions = EVENTS.map { |event_name| subscribe_to(event_name) }
      end

      def unsubscribe!
        return unless @subscriptions

        @subscriptions.each { |subscription| ActiveSupport::Notifications.unsubscribe(subscription) }
        @subscriptions = []
      end

      def subscribed?
        !!@subscriptions&.any?
      end

      private

      def subscription_allowed?
        SolidObserver.config.solid_cache_enabled? && !subscribed? && defined?(ActiveSupport::Notifications)
      end

      def subscribe_to(event_name)
        ActiveSupport::Notifications.subscribe(event_name) do |*args|
          event = ActiveSupport::Notifications::Event.new(*args)
          Services::RecordCacheEvent.call(event: event, buffer: CacheEventBuffer.instance)
        end
      end
    end
  end
end
