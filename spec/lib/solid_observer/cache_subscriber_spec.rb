# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CacheSubscriber do
  before do
    described_class.unsubscribe!
    allow(SolidObserver::Services::RecordCacheEvent).to receive(:call)
  end

  after { described_class.unsubscribe! }

  it "subscribes only when solid cache is enabled" do
    allow(SolidObserver.config).to receive(:solid_cache_enabled?).and_return(false)

    described_class.subscribe!

    expect(described_class.subscribed?).to be(false)
  end

  it "subscribes to configured cache events" do
    allow(SolidObserver.config).to receive(:solid_cache_enabled?).and_return(true)

    described_class.subscribe!
    ActiveSupport::Notifications.instrument("cache_read.active_support", {key: "secret-key", hit: true})

    expect(SolidObserver::Services::RecordCacheEvent).to have_received(:call).with(
      hash_including(buffer: SolidObserver::CacheEventBuffer.instance, event: be_a(ActiveSupport::Notifications::Event))
    )
  end

  it "unsubscribes from all notifications" do
    allow(SolidObserver.config).to receive(:solid_cache_enabled?).and_return(true)

    described_class.subscribe!
    described_class.unsubscribe!

    expect(described_class.subscribed?).to be(false)
  end
end
