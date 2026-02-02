# frozen_string_literal: true

module SolidObserver
  module Services
    # Flushes buffered events to the database using bulk insert.
    #
    # Attempts bulk insert with automatic fallback to smaller batches
    # if the initial insert fails.
    #
    # @example Flush events
    #   FlushEventBuffer.call(events)
    class FlushEventBuffer
      BATCH_SIZE = 100

      # @param events [Array<Hash>] Array of event data to insert
      # @return [Integer] Number of events successfully inserted
      def self.call(events)
        new(events).call
      end

      def initialize(events)
        @events = events
        @failed_count = 0
      end

      def call
        return 0 if @events.empty?

        QueueEvent.transaction do
          QueueEvent.insert_all!(@events)
        end

        @events.size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
        log_error("Bulk insert failed, retrying in batches: #{e.message}")
        retry_with_smaller_batches
      end

      private

      def retry_with_smaller_batches
        inserted = 0

        @events.each_slice(BATCH_SIZE) do |batch|
          QueueEvent.insert_all(batch, returning: false)
          inserted += batch.size
        rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
          @failed_count += batch.size
          log_warning("Failed to insert batch of #{batch.size} events: #{e.message}")
        end

        log_warning("#{@failed_count} events could not be saved") if @failed_count.positive?
        inserted
      end

      def log_error(message)
        Rails.logger.error("[SolidObserver] #{message}") if defined?(Rails)
      end

      def log_warning(message)
        Rails.logger.warn("[SolidObserver] #{message}") if defined?(Rails)
      end
    end
  end
end
