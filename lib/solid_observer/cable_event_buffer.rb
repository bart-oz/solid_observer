# frozen_string_literal: true

require "singleton"

require_relative "event_buffer_core"

module SolidObserver
  class CableEventBuffer
    include Singleton
    include EventBufferCore

    INITIAL_METRICS = EventBufferCore::INITIAL_METRICS

    def initialize
      initialize_event_buffer
    end

    private

    def flush_service
      Services::FlushCableEventBuffer
    end

    def log_label
      "Cable buffer"
    end
  end
end
