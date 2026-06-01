# frozen_string_literal: true

require "singleton"

module SolidObserver
  class CacheEventBuffer
    include Singleton

    def initialize
      @mutex = Mutex.new
      @buffer = []
    end

    def push(event_data)
      config = SolidObserver.config
      return unless config.persistence_mode?

      should_flush = buffer_ready_to_flush?(event_data, config.buffer_size)
      flush! if should_flush
    end

    def flush!
      events = @mutex.synchronize do
        buffered_events = @buffer.dup
        @buffer.clear
        buffered_events
      end
      return if events.empty?

      Services::FlushCacheEventBuffer.call(events)
    rescue => error
      @mutex.synchronize { @buffer = events + @buffer }
      Rails.logger&.error("[SolidObserver] Cache buffer flush failed: #{error.message}") if defined?(Rails)
    end

    def size
      @mutex.synchronize { @buffer.size }
    end

    def clear
      @mutex.synchronize { @buffer.clear }
    end

    private

    def buffer_ready_to_flush?(event_data, buffer_size)
      @mutex.synchronize do
        @buffer << event_data
        @buffer.size >= buffer_size
      end
    end
  end
end
