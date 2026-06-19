# frozen_string_literal: true

module SolidObserver
  module Services
    class FlushCableEventBuffer
      BATCH_SIZE = 100

      def self.call(events)
        new(events).call
      end

      def initialize(events)
        @events = events
      end

      def call
        return 0 if @events.empty?

        insert_all_events
        @events.size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
        fallback_insert_count(error)
      end

      private

      def insert_all_events
        CableEvent.transaction { CableEvent.insert_all!(@events) }
      end

      def fallback_insert_count(error)
        Rails.logger&.error("[SolidObserver] Cable bulk insert failed, retrying in batches: #{error.message}") if defined?(Rails)
        @events.each_slice(BATCH_SIZE).sum { |batch| insert_batch(batch) }
      end

      def insert_batch(batch)
        size = batch.size
        CableEvent.insert_all(batch, returning: false)
        size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
        handle_batch_insert_error(size, error)
      end

      def log_batch_warning(size, error)
        Rails.logger&.warn("[SolidObserver] Failed to insert cable batch of #{size} events: #{error.message}") if defined?(Rails)
      end

      def handle_batch_insert_error(size, error)
        log_batch_warning(size, error)
        0
      end
    end
  end
end
