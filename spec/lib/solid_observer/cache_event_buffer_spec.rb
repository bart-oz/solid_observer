# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CacheEventBuffer do
  subject(:buffer) { described_class.instance }

  let(:event_data) { {event_type: "cache_read", key_digest: "abc", recorded_at: Time.current, metadata: "{}"} }

  before do
    SolidObserver.reset_configuration!
    buffer.clear
    buffer.shutdown
    allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call)
  end

  after do
    buffer.clear
    buffer.shutdown
    SolidObserver.reset_configuration!
  end

  after(:all) do
    described_class.instance.clear
    described_class.instance.shutdown
  end

  it "buffers and flushes events when the configured threshold is reached" do
    SolidObserver.config.buffer_size = 2

    buffer.push(event_data)
    buffer.push(event_data.merge(event_type: "cache_write"))

    expect(SolidObserver::Services::FlushCacheEventBuffer).to have_received(:call).once
    expect(buffer.size).to eq(0)
  end

  it "does not buffer in realtime mode" do
    SolidObserver.config.storage_mode = :realtime

    buffer.push(event_data)

    expect(buffer.size).to eq(0)
  end

  it "clears buffered events without flushing" do
    buffer.push(event_data)

    buffer.clear

    expect(buffer.size).to eq(0)
    expect(SolidObserver::Services::FlushCacheEventBuffer).not_to have_received(:call)
  end

  describe "operational metrics" do
    it "returns QueueEventBuffer-compatible metric keys" do
      expect(buffer.metrics.keys).to eq(
        %i[
          size
          max_buffer_size
          flush_failures_count
          drops_count
          last_flush_at
          last_flush_duration_ms
          last_flush_error
        ]
      )
    end

    it "tracks successful flush metadata" do
      buffer.push(event_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:last_flush_at]).to be_a(Time)
      expect(metrics[:last_flush_duration_ms]).to be_a(Numeric)
      expect(metrics[:last_flush_error]).to be_nil
    end

    it "tracks flush failures, last error, and logged failures" do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call).and_raise(StandardError, "DB down")

      initial_failures = buffer.metrics[:flush_failures_count]
      buffer.push(event_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:flush_failures_count]).to eq(initial_failures + 1)
      expect(metrics[:last_flush_error]).to eq("DB down")
      expect(logger).to have_received(:error).with("[SolidObserver] Cache buffer flush failed: DB down")
    end
  end

  describe "timer lifecycle" do
    before do
      SolidObserver.config.buffer_size = 1000
    end

    it "starts lazily on first push" do
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil

      buffer.push(event_data)

      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil
    end

    it "flushes when the timer callback runs" do
      trigger_timer = stub_timer_callback

      buffer.push(event_data)
      trigger_timer.call

      expect(SolidObserver::Services::FlushCacheEventBuffer).to have_received(:call).with([event_data])
      expect(buffer.size).to eq(0)
    end
  end

  describe "shutdown" do
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 60
    end

    it "stops the timer and drains buffered events" do
      buffer.push(event_data)
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil

      buffer.shutdown

      expect(SolidObserver::Services::FlushCacheEventBuffer).to have_received(:call).with([event_data])
      expect(buffer.size).to eq(0)
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil
    end
  end

  describe "overflow policy" do
    before do
      SolidObserver.config.buffer_size = 3
      SolidObserver.config.max_buffer_size = 3
      allow(SolidObserver.config).to receive(:buffer_size).and_return(100)
    end

    context "when strategy is :drop_old" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_old
      end

      it "keeps newest events and tracks drops" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push(event_data.merge(id: i + 1)) }

        flushed_events = nil
        allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call) { |events| flushed_events = events }
        buffer.flush!

        expect(flushed_events.map { |event| event[:id] }).to eq([3, 4, 5])
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end

    context "when strategy is :drop_new" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_new
      end

      it "keeps oldest events and tracks drops" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push(event_data.merge(id: i + 1)) }

        flushed_events = nil
        allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call) { |events| flushed_events = events }
        buffer.flush!

        expect(flushed_events.map { |event| event[:id] }).to eq([1, 2, 3])
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end
  end

  describe "failure resilience" do
    before do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushCacheEventBuffer).to receive(:call).and_raise(StandardError, "DB down")
      SolidObserver.config.buffer_size = 25
      SolidObserver.config.max_buffer_size = 50
      SolidObserver.config.flush_interval = 60
      SolidObserver.config.buffer_overflow_strategy = :drop_old
    end

    it "keeps the buffer bounded during consecutive failing flushes" do
      10.times do
        100.times { buffer.push(event_data) }
        buffer.flush!
        expect(buffer.size).to be <= 50
      end
    end
  end

  def stub_timer_callback
    timer_callback = nil
    timer_task = instance_double(Concurrent::TimerTask, execute: nil, shutdown: nil, shuttingdown?: false)

    allow(Concurrent::TimerTask).to receive(:new) do |**_options, &block|
      timer_callback = block
      timer_task
    end

    -> { timer_callback.call }
  end
end
