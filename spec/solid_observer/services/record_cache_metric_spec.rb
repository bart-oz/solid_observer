# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::Services::RecordCacheMetric do
  let(:event_name) { "cache_read.active_support" }
  let(:started_at) { Time.current }
  let(:finished_at) { started_at + 0.01 }
  let(:payload) { {hit: true} }
  let(:event) { ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", payload) }
  let(:buffer) { instance_double(SolidObserver::CacheMetricBuffer, increment: nil) }

  it "buffers a metric in a 1-minute bucket without writing to the database" do
    travel_to(Time.parse("2026-06-01 12:34:45 UTC")) do
      described_class.call(event: event, buffer: buffer)
    end

    expect(buffer).to have_received(:increment).with(
      hash_including(
        event_type: "cache_read",
        period_start: Time.parse("2026-06-01 12:34:00 UTC"),
        operations_count: 1,
        hits_count: 1,
        misses_count: 0,
        errors_count: 0,
        duration_total: be > 0
      )
    )
  end

  it "tracks miss using explicit payload hit false" do
    miss_event = ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", {hit: false})

    described_class.call(event: miss_event, buffer: buffer)

    expect(buffer).to have_received(:increment).with(hash_including(hits_count: 0, misses_count: 1))
  end

  it "tracks errors using explicit exception payload" do
    error_event = ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", {exception: ["RuntimeError", "boom"]})

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:increment).with(hash_including(errors_count: 1))
  end
end
