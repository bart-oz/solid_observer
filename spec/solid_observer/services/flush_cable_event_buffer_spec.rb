# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::FlushCableEventBuffer do
  let(:events) { [{event_type: "broadcast", broadcasting_digest: "abc", recorded_at: Time.current, metadata: "{}"}] }

  it "bulk inserts cable events" do
    allow(SolidObserver::CableEvent).to receive(:transaction).and_yield
    allow(SolidObserver::CableEvent).to receive(:insert_all!)

    described_class.call(events)

    expect(SolidObserver::CableEvent).to have_received(:insert_all!).with(events)
  end

  it "falls back to smaller batches on statement failure" do
    allow(SolidObserver::CableEvent).to receive(:transaction).and_yield
    allow(SolidObserver::CableEvent).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, "boom")
    allow(SolidObserver::CableEvent).to receive(:insert_all).and_return(true)
    allow(Rails).to receive(:logger).and_return(instance_double(Logger, error: nil, warn: nil))

    described_class.call(events)

    expect(SolidObserver::CableEvent).to have_received(:insert_all).at_least(:once)
  end

  it "logs a warning and returns zero when fallback batch inserts also fail" do
    logger = instance_double(Logger, error: nil, warn: nil)

    allow(SolidObserver::CableEvent).to receive(:transaction).and_yield
    allow(SolidObserver::CableEvent).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, "bulk boom")
    allow(SolidObserver::CableEvent).to receive(:insert_all).with(events, returning: false).and_raise(
      ActiveRecord::StatementInvalid,
      "batch boom"
    )
    allow(Rails).to receive(:logger).and_return(logger)

    expect(described_class.call(events)).to eq(0)
    expect(logger).to have_received(:warn).with(
      "[SolidObserver] Failed to insert cable batch of 1 events: batch boom"
    )
  end
end
