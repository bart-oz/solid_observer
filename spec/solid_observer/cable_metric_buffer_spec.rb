# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::CableMetricBuffer do
  subject(:buffer) { described_class.instance }

  let(:period_start) { Time.parse("2026-06-01 12:34:00 UTC") }
  let(:metric_data) do
    {
      period_start: period_start,
      broadcasts_count: 1,
      transmissions_count: 0,
      confirmations_count: 0,
      rejections_count: 0,
      perform_actions_count: 0,
      errors_count: 0
    }
  end

  before(:all) do
    connection = SolidObserver::CableMetric.connection
    next if connection.table_exists?(:solid_observer_cable_metrics)

    connection.create_table :solid_observer_cable_metrics do |t|
      t.datetime :period_start, null: false
      t.bigint :broadcasts_count, null: false, default: 0
      t.bigint :transmissions_count, null: false, default: 0
      t.bigint :confirmations_count, null: false, default: 0
      t.bigint :rejections_count, null: false, default: 0
      t.bigint :perform_actions_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
    end

    connection.add_index :solid_observer_cable_metrics, :period_start, unique: true,
      name: "idx_solid_observer_cable_metrics_unique"
  end

  before do
    SolidObserver.reset_configuration!
    SolidObserver::CableMetric.delete_all
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
    buffer.increment(metric_data.merge(transmissions_count: 1, errors_count: 1))
    buffer.flush!

    metric = SolidObserver::CableMetric.find_by!(period_start: period_start)
    expect(metric.broadcasts_count).to eq(2)
    expect(metric.transmissions_count).to eq(1)
    expect(metric.confirmations_count).to eq(0)
    expect(metric.rejections_count).to eq(0)
    expect(metric.perform_actions_count).to eq(0)
    expect(metric.errors_count).to eq(1)
    expect(buffer.size).to eq(0)
  end

  it "persists metrics when the timer callback flushes" do
    SolidObserver.config.buffer_size = 1000
    trigger_timer = stub_timer_callback

    buffer.increment(metric_data.merge(rejections_count: 1))
    trigger_timer.call

    metric = SolidObserver::CableMetric.find_by!(period_start: period_start)
    expect(metric.broadcasts_count).to eq(1)
    expect(metric.rejections_count).to eq(1)
  end

  it "does not buffer in realtime mode" do
    SolidObserver.config.storage_mode = :realtime

    buffer.increment(metric_data)

    expect(buffer.size).to eq(0)
  end

  it "clears buffered metrics without flushing" do
    allow(SolidObserver::Services::FlushCableMetrics).to receive(:call)

    buffer.increment(metric_data)
    buffer.clear

    expect(buffer.size).to eq(0)
    expect(SolidObserver::Services::FlushCableMetrics).not_to have_received(:call)
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
      buffer.increment(metric_data.merge(perform_actions_count: 1))
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil

      buffer.shutdown

      metric = SolidObserver::CableMetric.find_by!(period_start: period_start)
      expect(metric.broadcasts_count).to eq(1)
      expect(metric.perform_actions_count).to eq(1)
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
      allow(SolidObserver::Services::FlushCableMetrics).to receive(:call).and_raise(ActiveRecord::StatementInvalid, "DB down")

      initial_failures = buffer.metrics[:flush_failures_count]
      buffer.increment(metric_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:flush_failures_count]).to eq(initial_failures + 1)
      expect(metrics[:last_flush_error]).to eq("DB down")
      expect(buffer.size).to eq(1)
      expect(logger).to have_received(:error).with("[SolidObserver] Cable metric buffer flush failed: DB down")
    end
  end

  describe "overflow policy" do
    before do
      SolidObserver.config.buffer_size = 3
      SolidObserver.config.max_buffer_size = 3
      allow(SolidObserver.config).to receive(:buffer_size).and_return(100)
    end

    context "when strategy is :drop_old" do
      before { SolidObserver.config.buffer_overflow_strategy = :drop_old }

      it "keeps newest metric buckets and tracks dropped counters" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.increment(metric_data.merge(period_start: period_start + i.minutes)) }

        buffer.flush!

        expect(SolidObserver::CableMetric.pluck(:period_start)).to contain_exactly(
          period_start + 2.minutes,
          period_start + 3.minutes,
          period_start + 4.minutes
        )
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end

    context "when strategy is :drop_new" do
      before { SolidObserver.config.buffer_overflow_strategy = :drop_new }

      it "keeps oldest metric buckets and tracks dropped counters" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.increment(metric_data.merge(period_start: period_start + i.minutes)) }

        buffer.flush!

        expect(SolidObserver::CableMetric.pluck(:period_start)).to contain_exactly(
          period_start,
          period_start + 1.minute,
          period_start + 2.minutes
        )
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
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
