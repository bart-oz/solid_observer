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

        bulk_insert
        @events.size
      rescue ActiveRecord::RecordInvalid, ActiveRecord::StatementInvalid => e
        handle_bulk_insert_failure(e)
      end

      private

      def bulk_insert
        QueueEvent.transaction do
          QueueEvent.insert_all!(@events)
        end
      end

      def handle_bulk_insert_failure(error)
        log_error("Bulk insert failed, retrying in batches: #{error.message}")
        retry_with_smaller_batches
      end

      def retry_with_smaller_batches
        inserted = @events.each_slice(BATCH_SIZE).sum { |batch| insert_batch(batch) }
        log_failed_count if @failed_count.positive?
        inserted
      end

      def insert_batch(batch)
        QueueEvent.insert_all(batch, returning: false)
        batch.size
      rescue ActiveRecord::StatementInvalid, ActiveRecord::RecordInvalid => e
        register_failed_batch(batch, e)
        0
      end

      def register_failed_batch(batch, error)
        batch_size = batch.size
        @failed_count += batch_size
        log_warning("Failed to insert batch of #{batch_size} events: #{error.message}")
      end

      def log_failed_count
        log_warning("#{@failed_count} events could not be saved")
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
