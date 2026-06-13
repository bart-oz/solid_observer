# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::CacheMetricBuffer do
  subject(:buffer) { described_class.instance }

  let(:period_start) { Time.parse("2026-06-01 12:34:00 UTC") }
  let(:metric_data) do
    {
      event_type: "cache_read",
      period_start: period_start,
      operations_count: 1,
      hits_count: 1,
      misses_count: 0,
      errors_count: 0,
      duration_total: 0.01
    }
  end

  before(:all) do
    connection = SolidObserver::CacheMetric.connection
    next if connection.table_exists?(:solid_observer_cache_metrics)

    connection.create_table :solid_observer_cache_metrics do |t|
      t.string :event_type, null: false, limit: 64
      t.datetime :period_start, null: false
      t.bigint :operations_count, null: false, default: 0
      t.bigint :hits_count, null: false, default: 0
      t.bigint :misses_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
      t.float :duration_total, null: false, default: 0.0
    end

    connection.add_index :solid_observer_cache_metrics, [:event_type, :period_start], unique: true,
      name: "idx_solid_observer_cache_metrics_unique"
    connection.add_index :solid_observer_cache_metrics, :period_start
  end

  before do
    SolidObserver.reset_configuration!
    SolidObserver::CacheMetric.delete_all
    buffer.clear
    buffer.shutdown
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

  it "aggregates metrics in memory and flushes explicitly" do
    SolidObserver.config.buffer_size = 1000

    buffer.increment(metric_data)
    buffer.increment(metric_data.merge(hits_count: 0, misses_count: 1, duration_total: 0.02))
    buffer.flush!

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read", period_start: period_start)
    expect(metric.operations_count).to eq(2)
    expect(metric.hits_count).to eq(1)
    expect(metric.misses_count).to eq(1)
    expect(metric.errors_count).to eq(0)
    expect(metric.duration_total).to be_within(0.0001).of(0.03)
    expect(buffer.size).to eq(0)
  end

  it "persists metrics when the timer callback flushes" do
    SolidObserver.config.buffer_size = 1000
    trigger_timer = stub_timer_callback

    buffer.increment(metric_data.merge(errors_count: 1, duration_total: 0.05))
    trigger_timer.call

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read", period_start: period_start)
    expect(metric.operations_count).to eq(1)
    expect(metric.hits_count).to eq(1)
    expect(metric.errors_count).to eq(1)
    expect(metric.duration_total).to be_within(0.0001).of(0.05)
  end

  it "does not buffer in realtime mode" do
    SolidObserver.config.storage_mode = :realtime

    buffer.increment(metric_data)

    expect(buffer.size).to eq(0)
  end

  it "clears buffered metrics without flushing" do
    allow(SolidObserver::Services::FlushCacheMetrics).to receive(:call)

    buffer.increment(metric_data)
    buffer.clear

    expect(buffer.size).to eq(0)
    expect(SolidObserver::Services::FlushCacheMetrics).not_to have_received(:call)
  end

  describe "timer lifecycle" do
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 60
    end

    it "starts lazily on first increment" do
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil

      buffer.increment(metric_data)

      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil
    end
  end

  describe "shutdown" do
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 60
    end

    it "stops the timer and persists buffered metric buckets" do
      buffer.increment(metric_data.merge(duration_total: 0.04))
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil

      buffer.shutdown

      metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read", period_start: period_start)
      expect(metric.operations_count).to eq(1)
      expect(metric.hits_count).to eq(1)
      expect(metric.duration_total).to be_within(0.0001).of(0.04)
      expect(buffer.size).to eq(0)
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil
    end
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
      buffer.increment(metric_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:last_flush_at]).to be_a(Time)
      expect(metrics[:last_flush_duration_ms]).to be_a(Numeric)
      expect(metrics[:last_flush_error]).to be_nil
    end

    it "tracks flush failures, last error, and logged failures" do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushCacheMetrics).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "DB down")

      initial_failures = buffer.metrics[:flush_failures_count]
      buffer.increment(metric_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:flush_failures_count]).to eq(initial_failures + 1)
      expect(metrics[:last_flush_error]).to eq("DB down")
      expect(buffer.size).to eq(1)
      expect(logger).to have_received(:error).with("[SolidObserver] Cache metric buffer flush failed: DB down")
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

      it "keeps newest metric buckets and tracks dropped operations" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.increment(metric_data.merge(event_type: "cache_#{i}")) }

        buffer.flush!

        expect(SolidObserver::CacheMetric.pluck(:event_type)).to contain_exactly("cache_2", "cache_3", "cache_4")
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end

    context "when strategy is :drop_new" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_new
      end

      it "keeps oldest metric buckets and tracks dropped operations" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.increment(metric_data.merge(event_type: "cache_#{i}")) }

        buffer.flush!

        expect(SolidObserver::CacheMetric.pluck(:event_type)).to contain_exactly("cache_0", "cache_1", "cache_2")
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end
  end

  describe "failure resilience" do
    before do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushCacheMetrics).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "DB down")
      SolidObserver.config.buffer_size = 5
      SolidObserver.config.max_buffer_size = 10
      SolidObserver.config.buffer_overflow_strategy = :drop_old
    end

    it "keeps the buffer bounded during consecutive failing flushes" do
      10.times do |batch|
        20.times { |i| buffer.increment(metric_data.merge(event_type: "cache_#{batch}_#{i}")) }
        buffer.flush!
        expect(buffer.size).to be <= 10
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
