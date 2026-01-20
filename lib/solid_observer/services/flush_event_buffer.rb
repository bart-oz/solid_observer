# frozen_string_literal: true

module SolidObserver
  module Services
    class FlushEventBuffer
      def self.call(events)
        new(events).call
      end

      def initialize(events)
        @events = events
      end

      def call
        return if @events.empty?

        QueueEvent.transaction do
          QueueEvent.insert_all!(@events)
        end
      rescue ActiveRecord::RecordInvalid
        retry_with_smaller_batches
      rescue => e
        Rails.logger.error "[SolidObserver] Event buffer flush failed: #{e.message}" if defined?(Rails)
        raise
      end

      private

      def retry_with_smaller_batches
        @events.each_slice(100) do |batch|
          QueueEvent.insert_all(batch, returning: false)
        rescue => e
          Rails.logger.warn "[SolidObserver] Failed to insert batch: #{e.message}" if defined?(Rails)
        end
      end
    end
  end
end
