# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::FlushCacheEventBuffer do
  let(:events) { [{event_type: "cache_read", key_digest: "abc", recorded_at: Time.current, metadata: "{}"}] }

  it "bulk inserts cache events" do
    allow(SolidObserver::CacheEvent).to receive(:transaction).and_yield
    allow(SolidObserver::CacheEvent).to receive(:insert_all!)

    described_class.call(events)

    expect(SolidObserver::CacheEvent).to have_received(:insert_all!).with(events)
  end

  it "falls back to smaller batches on statement failure" do
    allow(SolidObserver::CacheEvent).to receive(:transaction).and_yield
    allow(SolidObserver::CacheEvent).to receive(:insert_all!).and_raise(ActiveRecord::StatementInvalid, "boom")
    allow(SolidObserver::CacheEvent).to receive(:insert_all).and_return(true)
    allow(Rails).to receive(:logger).and_return(instance_double(Logger, error: nil, warn: nil))

    described_class.call(events)

    expect(SolidObserver::CacheEvent).to have_received(:insert_all).at_least(:once)
  end
end
