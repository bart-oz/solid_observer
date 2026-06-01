# frozen_string_literal: true

module SolidObserver
  module Services
    class FlushCacheEventBuffer
      BATCH_SIZE = 100

      def self.call(events)
        new(events).call
      end

      def initialize(events)
        @events = events
      end

      def call
        return 0 if @events.empty?

        CacheEvent.transaction { CacheEvent.insert_all!(@events) }
        @events.size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
        Rails.logger&.error("[SolidObserver] Cache bulk insert failed, retrying in batches: #{error.message}") if defined?(Rails)
        @events.each_slice(BATCH_SIZE).sum { |batch| insert_batch(batch) }
      end

      private

      def insert_batch(batch)
        CacheEvent.insert_all(batch, returning: false)
        batch.size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => error
        Rails.logger&.warn("[SolidObserver] Failed to insert cache batch of #{batch.size} events: #{error.message}") if defined?(Rails)
        0
      end
    end
  end
end
