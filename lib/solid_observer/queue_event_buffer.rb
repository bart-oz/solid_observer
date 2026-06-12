# frozen_string_literal: true

require "singleton"

require_relative "event_buffer_core"

module SolidObserver
  # Thread-safe buffer for collecting queue events before batch insertion.
  class QueueEventBuffer
    include Singleton
    include EventBufferCore

    INITIAL_METRICS = EventBufferCore::INITIAL_METRICS

    def initialize
      initialize_event_buffer
    end

    private

    def flush_service
      Services::FlushEventBuffer
    end

    def log_label
      "Buffer"
    end
  end
end
