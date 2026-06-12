# frozen_string_literal: true

require "spec_helper"
require_relative "../support/shared_examples_for_event_buffer"

RSpec.describe SolidObserver::QueueEventBuffer do
  it_behaves_like "an event buffer",
    flush_service: SolidObserver::Services::FlushEventBuffer,
    log_label: "Buffer",
    event_factory: -> { {event_type: "test", recorded_at: Time.current} }
end
