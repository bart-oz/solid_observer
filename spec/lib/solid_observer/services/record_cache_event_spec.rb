# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::RecordCacheEvent do
  let(:buffer) { instance_double(SolidObserver::CacheEventBuffer, push: nil) }
  let(:payload) { {key: "user:42", hit: true, super_operation: :fetch} }
  let(:event) { ActiveSupport::Notifications::Event.new("cache_read.active_support", Time.current, Time.current + 0.01, "id", payload) }

  it "stores safe metadata and a non-raw key digest" do
    allow(Kernel).to receive(:rand).and_return(1.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      event_type: "cache_read",
      key_digest: Digest::SHA256.hexdigest("user:42"),
      hit: true,
      duration: be > 0,
      error_class: nil,
      error_message: nil,
      metadata: satisfy { |json| JSON.parse(json).keys.none? { |key| key == "key" || key == "value" } }
    ))
  end

  it "stores unsampled events when slow" do
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 0.001, cache_store_errors: true)

    described_class.call(event: event, buffer: buffer)

    expect(buffer).to have_received(:push)
  end

  it "skips unsampled fast non-error events" do
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)

    described_class.call(event: event, buffer: buffer)

    expect(buffer).not_to have_received(:push)
  end
end
