# frozen_string_literal: true

require "singleton"

require_relative "event_buffer_core"

module SolidObserver
  class CacheEventBuffer
    include Singleton
    include EventBufferCore

    INITIAL_METRICS = EventBufferCore::INITIAL_METRICS

    def initialize
      initialize_event_buffer
    end

    private

    def flush_service
      Services::FlushCacheEventBuffer
    end

    def log_label
      "Cache buffer"
    end
  end
end
