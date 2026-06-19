# frozen_string_literal: true

require "spec_helper"
require_relative "../support/shared_examples_for_event_buffer"

RSpec.describe SolidObserver::CableEventBuffer do
  it_behaves_like "an event buffer",
    flush_service: SolidObserver::Services::FlushCableEventBuffer,
    log_label: "Cable buffer",
    event_factory: -> { {event_type: "broadcast", broadcasting_digest: "abc", recorded_at: Time.current, metadata: "{}"} }
end
