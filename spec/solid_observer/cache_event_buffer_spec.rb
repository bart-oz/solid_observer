# frozen_string_literal: true

require "spec_helper"
require_relative "../support/shared_examples_for_event_buffer"

RSpec.describe SolidObserver::CacheEventBuffer do
  it_behaves_like "an event buffer",
    flush_service: SolidObserver::Services::FlushCacheEventBuffer,
    log_label: "Cache buffer",
    event_factory: -> { {event_type: "cache_read", key_digest: "abc", recorded_at: Time.current, metadata: "{}"} }
end
