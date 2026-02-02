# frozen_string_literal: true

require "singleton"

module SolidObserver
  # Thread-safe buffer for collecting queue events before batch insertion.
  #
  # Events are buffered in memory and flushed either when:
  # - Buffer size reaches the configured threshold
  # - Flush interval timer expires
  #
  # @example Push an event to the buffer
  #   QueueEventBuffer.instance.push(event_data)
  class QueueEventBuffer
    include Singleton

    def initialize
      @mutex = Mutex.new
      @buffer = []
      @flush_scheduled = false
    end

    # Adds an event to the buffer and triggers flush if threshold reached.
    #
    # @param event_data [Hash] Event data to buffer
    # @return [void]
    def push(event_data)
      should_flush = false

      @mutex.synchronize do
        @buffer << event_data
        schedule_flush unless @flush_scheduled
        should_flush = @buffer.size >= SolidObserver.config.buffer_size
      end

      flush! if should_flush
    end

    # Flushes all buffered events to the database.
    #
    # @return [void]
    def flush!
      events_to_flush = nil

      @mutex.synchronize do
        return if @buffer.empty?
        events_to_flush = @buffer.dup
        @buffer.clear
      end

      Services::FlushEventBuffer.call(events_to_flush)
    rescue => e
      @mutex.synchronize { @buffer.unshift(*events_to_flush) }
      Rails.logger&.error "[SolidObserver] Buffer flush failed: #{e.message}" if defined?(Rails)
    end

    def size
      @mutex.synchronize { @buffer.size }
    end

    def clear
      @mutex.synchronize { @buffer.clear }
    end

    private

    def schedule_flush
      @flush_scheduled = true
      thread = Thread.new do
        sleep SolidObserver.config.flush_interval
        @mutex.synchronize { @flush_scheduled = false }
        flush!
      rescue => e
        Rails.logger&.error "[SolidObserver] Scheduled flush failed: #{e.message}" if defined?(Rails)
      end
      thread.name = "SolidObserver::QueueEventBuffer#flush"
      thread.report_on_exception = false
    end
  end
end
