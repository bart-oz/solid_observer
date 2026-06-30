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

  it "stores safe metadata, a non-raw key digest, and a correlation_id" do
    allow(Kernel).to receive(:rand).and_return(1.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      event_type: "cache_read",
      correlation_id: a_string_matching(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/),
      key_digest: Digest::SHA256.hexdigest("user:42"),
      hit: true,
      duration: be > 0,
      error_class: nil,
      error_message: nil,
      metadata: satisfy { |json| JSON.parse(json).keys.none? { |key| key == "key" || key == "value" } }
    ))
  end

  it "does not persist raw cache keys, values, or job arguments" do
    allow(Kernel).to receive(:rand).and_return(1.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: event, buffer: buffer)

    expect(buffer).to have_received(:push).with(satisfy { |data|
      data.keys.none? { |key| %i[key value arguments args].include?(key) }
    })
  end

  it "records metrics even when raw event is not sampled" do
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)
    allow(SolidObserver::Services::RecordCacheMetric).to receive(:call)

    described_class.call(event: event, buffer: buffer)

    expect(SolidObserver::Services::RecordCacheMetric).to have_received(:call).with(event: event)
    expect(buffer).not_to have_received(:push)
  end

  it "skips SolidObserver-internal cache keys for both metrics and event storage" do
    internal_event = ActiveSupport::Notifications::Event.new(
      "cache_write.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: "solid_observer/chart_buffer/ready_samples", hit: true, super_operation: :fetch}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 0.0, cache_store_errors: true)
    allow(SolidObserver::Services::RecordCacheMetric).to receive(:call)

    described_class.call(event: internal_event, buffer: buffer)

    expect(SolidObserver::Services::RecordCacheMetric).not_to have_received(:call)
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

  it "normalizes Hash keys before hashing" do
    hash_event = ActiveSupport::Notifications::Event.new(
      "cache_read.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: {b: 2, a: 1}, hit: true}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: hash_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      key_digest: Digest::SHA256.hexdigest("a,b")
    ))
  end

  it "normalizes Array keys before hashing" do
    array_event = ActiveSupport::Notifications::Event.new(
      "cache_read_multi.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: ["b", "a"], hits: ["a"]}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: array_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      key_digest: Digest::SHA256.hexdigest("a,b")
    ))
  end

  it "records hit state and hits_count for multi-key operations" do
    multi_key_event = ActiveSupport::Notifications::Event.new(
      "cache_read_multi.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: ["a", "b"], hits: ["a"]}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 1.0, cache_slow_threshold: 1.0, cache_store_errors: true)

    described_class.call(event: multi_key_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      hit: true,
      metadata: satisfy { |json|
        JSON.parse(json).slice("hits_count", "key_size") == {"hits_count" => 1, "key_size" => 2}
      }
    ))
  end

  it "records exception_object details on stored events" do
    error_event = ActiveSupport::Notifications::Event.new(
      "cache_read.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: "user:42", exception_object: StandardError.new("Cache timeout")}
    )

    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      error_class: "StandardError",
      error_message: "Cache timeout"
    ))
  end

  it "records explicit exception payload details on stored events" do
    error_event = ActiveSupport::Notifications::Event.new(
      "cache_read.active_support",
      Time.current,
      Time.current + 0.01,
      "id",
      {key: "user:42", exception: ["StandardError", "Cache timeout"]}
    )

    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive_messages(cache_sampling_rate: 0.0, cache_slow_threshold: 10.0, cache_store_errors: true)

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      error_class: "StandardError",
      error_message: "Cache timeout"
    ))
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
