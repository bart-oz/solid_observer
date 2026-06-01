# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CacheEventBuffer do
  subject(:buffer) { described_class.instance }

  before do
    buffer.clear
    allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call)
  end

  after { buffer.clear }

  it "buffers and flushes events" do
    allow(SolidObserver.config).to receive(:buffer_size).and_return(2)

    buffer.push({event_type: "cache_read", recorded_at: Time.current})
    buffer.push({event_type: "cache_write", recorded_at: Time.current})

    expect(SolidObserver::Services::FlushCacheEventBuffer).to have_received(:call).once
    expect(buffer.size).to eq(0)
  end

  it "does not buffer in realtime mode" do
    allow(SolidObserver.config).to receive(:persistence_mode?).and_return(false)

    buffer.push({event_type: "cache_read", recorded_at: Time.current})

    expect(buffer.size).to eq(0)
  end
end
