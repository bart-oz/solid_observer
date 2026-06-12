# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::RecordCacheEvent do
  let(:buffer) { instance_double(SolidObserver::CacheEventBuffer, push: nil) }
  let(:payload) { {key: "user:42", hit: true, super_operation: :fetch} }
  let(:event) { ActiveSupport::Notifications::Event.new("cache_read.active_support", Time.current, Time.current + 0.01, "id", payload) }

  before do
    SolidObserver.reset_configuration!
    SolidObserver::CacheMetricBuffer.instance.clear
    SolidObserver::CacheMetricBuffer.instance.shutdown
  end

  after do
    SolidObserver::CacheMetricBuffer.instance.clear
    SolidObserver::CacheMetricBuffer.instance.shutdown
    SolidObserver.reset_configuration!
  end

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

  it "records metrics even when raw event is not sampled" do
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)
    allow(SolidObserver::Services::RecordCacheMetric).to receive(:call)

    described_class.call(event: event, buffer: buffer)

    expect(SolidObserver::Services::RecordCacheMetric).to have_received(:call).with(event: event)
    expect(buffer).not_to have_received(:push)
  end

  it "emits no solid_observer_cache_metrics SQL on the notification callback path" do
    SolidObserver.config.buffer_size = 1000
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)

    sql = capture_sql do
      described_class.call(event: event, buffer: buffer)
    end

    expect(sql.grep(/solid_observer_cache_metrics/i)).to be_empty
    expect(SolidObserver::CacheMetricBuffer.instance.size).to eq(1)
    expect(buffer).not_to have_received(:push)
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

  it "re-raises NameError wiring failures" do
    allow(SolidObserver::Services::RecordCacheMetric).to receive(:call).and_raise(
      NameError.new("uninitialized constant SolidObserver::Services::RecordCacheMetric")
    )

    expect {
      described_class.call(event: event, buffer: buffer)
    }.to raise_error(NameError, /RecordCacheMetric/)

    expect(buffer).not_to have_received(:push)
  end

  it "logs and swallows ordinary StandardError failures" do
    logger = instance_double(Logger, warn: nil)

    allow(Rails).to receive(:logger).and_return(logger)
    allow(SolidObserver::Services::RecordCacheMetric).to receive(:call).and_raise(
      ActiveRecord::StatementInvalid.new("missing table")
    )

    expect {
      described_class.call(event: event, buffer: buffer)
    }.not_to raise_error

    expect(logger).to have_received(:warn).with(
      "[SolidObserver] Cache event recording failed: missing table"
    )
    expect(buffer).not_to have_received(:push)
  end

  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _id, sql_payload|
      statements << sql_payload[:sql]
    end

    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
