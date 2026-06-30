# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/solid_observer/services/cache_stats"

RSpec.describe SolidObserver::Services::CacheStats do
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
  end

  before(:all) do
    connection = SolidObserver::CacheEvent.connection
    next if connection.table_exists?(:solid_observer_cache_events)

    connection.create_table :solid_observer_cache_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.boolean :hit
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
  end

  before do
    SolidObserver::CacheMetric.delete_all
    SolidObserver::CacheEvent.delete_all
  end

  after { SolidObserver.reset_configuration! }

  describe ".parse_range" do
    it "returns the requested range when it is supported" do
      expect(described_class.parse_range("1h")).to eq("1h")
    end

    it "falls back to the default range for unsupported values" do
      expect(described_class.parse_range("bogus")).to eq("15m")
    end
  end

  describe ".range_duration" do
    it "returns the configured duration for a range key" do
      expect(described_class.range_duration("1h")).to eq(1.hour)
    end

    it "uses the default duration for unsupported values" do
      expect(described_class.range_duration("bogus")).to eq(15.minutes)
    end
  end

  describe described_class::TrendData do
    let(:fixed_time) { Time.utc(2026, 6, 3, 12, 0, 0) }

    it "returns the empty trend payload when no metric rows exist" do
      result = described_class.new(metric_rows: [], window: 15.minutes, current_time: fixed_time).to_h

      expect(result).to eq(SolidObserver::Services::CacheStats::ACTIVITY_TREND_EMPTY)
      expect(result).not_to be(SolidObserver::Services::CacheStats::ACTIVITY_TREND_EMPTY)
    end

    it "buckets metric rows and builds hit-rate, operations, and errors series" do
      result = described_class.new(
        metric_rows: [
          [fixed_time - 14.minutes + 45.seconds, 10, 7, 3, 1, 1.2],
          [fixed_time - 14.minutes + 10.seconds, 2, 0, 0, 1, 0.4],
          [fixed_time - 2.minutes + 30.seconds, 5, 4, 1, 0, 0.5]
        ],
        window: 15.minutes,
        current_time: fixed_time
      ).to_h

      hit_rate_by_time = result[:hit_rate].to_h { |point| [point[:t], point[:v]] }
      operations_by_time = result[:operations].to_h { |point| [point[:t], point[:v]] }
      errors_by_time = result[:errors].to_h { |point| [point[:t], point[:v]] }

      expect(result[:available]).to be(true)
      expect(result[:hit_rate].size).to eq(16)
      expect(hit_rate_by_time[(fixed_time - 14.minutes).to_i]).to eq(0.7)
      expect(operations_by_time[(fixed_time - 14.minutes).to_i]).to eq(12)
      expect(errors_by_time[(fixed_time - 14.minutes).to_i]).to eq(2)
      expect(hit_rate_by_time[(fixed_time - 2.minutes).to_i]).to eq(0.8)
      expect(operations_by_time[(fixed_time - 2.minutes).to_i]).to eq(5)
      expect(errors_by_time[(fixed_time - 2.minutes).to_i]).to eq(0)
      expect(hit_rate_by_time[(fixed_time - 13.minutes).to_i]).to eq(0.0)
      expect(operations_by_time[(fixed_time - 13.minutes).to_i]).to eq(0)
      expect(errors_by_time[(fixed_time - 13.minutes).to_i]).to eq(0)
    end
  end

  describe described_class::StabilityData do
    let(:fixed_time) { Time.utc(2026, 6, 3, 12, 0, 0) }

    around do |example|
      previous_threshold = SolidObserver.config.cache_slow_threshold
      SolidObserver.config.cache_slow_threshold = 0.1

      travel_to(fixed_time) { example.run }
    ensure
      SolidObserver.config.cache_slow_threshold = previous_threshold
    end

    def stability_data
      described_class.new(window: 15.minutes, current_time: Time.current).to_h
    end

    it "classifies the range as stable when only fast successful events exist" do
      SolidObserver::CacheEvent.create!(
        event_type: "cache_read",
        key_digest: "stable-event",
        hit: true,
        duration: 0.05,
        metadata: "{}",
        recorded_at: 5.minutes.ago
      )

      expect(stability_data).to include(
        available: true,
        state: :stable,
        error_count: 0,
        slow_count: 0,
        latest_recorded_at: nil
      )
    end

    it "classifies the range as degraded when slow events exist without errors" do
      recorded_at = 4.minutes.ago
      SolidObserver::CacheEvent.create!(
        event_type: "cache_write",
        key_digest: "slow-event",
        duration: 0.25,
        metadata: "{}",
        recorded_at: recorded_at
      )

      expect(stability_data).to include(
        available: true,
        state: :degraded,
        error_count: 0,
        slow_count: 1,
        latest_recorded_at: recorded_at
      )
    end

    it "keeps latest_recorded_at scoped to slow or errored events" do
      slow_recorded_at = 4.minutes.ago
      SolidObserver::CacheEvent.create!(
        event_type: "cache_write",
        key_digest: "slow-event",
        duration: 0.25,
        metadata: "{}",
        recorded_at: slow_recorded_at
      )
      SolidObserver::CacheEvent.create!(
        event_type: "cache_write",
        key_digest: "fast-event",
        duration: 0.01,
        metadata: "{}",
        recorded_at: 1.minute.ago
      )

      expect(stability_data).to include(
        available: true,
        state: :degraded,
        error_count: 0,
        slow_count: 1,
        latest_recorded_at: slow_recorded_at
      )
    end

    it "classifies the range as critical when error events are present" do
      SolidObserver::CacheEvent.create!(
        event_type: "cache_write",
        key_digest: "slow-event",
        duration: 0.25,
        metadata: "{}",
        recorded_at: 6.minutes.ago
      )
      SolidObserver::CacheEvent.create!(
        event_type: "cache_fetch",
        key_digest: "error-event",
        duration: 0.02,
        error_class: "RuntimeError",
        error_message: "hidden from UI",
        metadata: "{}",
        recorded_at: 2.minutes.ago
      )

      expect(stability_data).to include(
        available: true,
        state: :critical,
        error_count: 1,
        slow_count: 1,
        latest_recorded_at: 2.minutes.ago
      )
    end
  end

  it "returns dashboard-ready aggregated cache stats for window" do
    now = Time.current
    SolidObserver::CacheMetric.create!(
      event_type: "cache_read",
      period_start: now.beginning_of_minute,
      operations_count: 10,
      hits_count: 7,
      misses_count: 3,
      errors_count: 1,
      duration_total: 1.5
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:operations_count]).to eq(10)
    expect(stats[:hits_count]).to eq(7)
    expect(stats[:misses_count]).to eq(3)
    expect(stats[:errors_count]).to eq(1)
    expect(stats[:duration_total]).to eq(1.5)
    expect(stats[:hit_rate]).to eq(0.7)
    expect(stats[:error_rate]).to eq(0.1)
    expect(stats[:avg_duration]).to eq(0.15)
    expect(stats[:throughput]).to eq(2.0)
  end

  it "computes hit_rate from explicit read outcomes only" do
    now = Time.current
    SolidObserver::CacheMetric.create!(
      event_type: "cache_read",
      period_start: now.beginning_of_minute,
      operations_count: 10,
      hits_count: 7,
      misses_count: 3,
      errors_count: 1,
      duration_total: 1.5
    )

    SolidObserver::CacheMetric.create!(
      event_type: "cache_write",
      period_start: now.beginning_of_minute,
      operations_count: 40,
      hits_count: 0,
      misses_count: 0,
      errors_count: 0,
      duration_total: 0.8
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:operations_count]).to eq(50)
    expect(stats[:hits_count]).to eq(7)
    expect(stats[:misses_count]).to eq(3)
    expect(stats[:hit_rate]).to eq(0.7)
  end

  it "returns safe fallback when metric table query fails" do
    allow(SolidObserver::CacheMetric).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("missing table"))

    stats = described_class.call(window: 5.minutes)

    expect(stats).to include(
      hit_rate: 0.0,
      throughput: 0.0,
      error_rate: 0.0,
      avg_duration: 0.0,
      operations_count: 0,
      hits_count: 0,
      misses_count: 0,
      errors_count: 0,
      duration_total: 0.0
    )
    expect(stats[:error]).to eq("Service temporarily unavailable")
  end

  it "degrades stability on ActiveRecord::StatementInvalid from cache events query, preserving other data" do
    allow(SolidObserver::CacheEvent).to receive(:where).and_raise(
      ActiveRecord::StatementInvalid.new("no such table: solid_observer_cache_events")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats).not_to have_key(:error)
    expect(stats[:stability]).to include(available: false, state: :stable)
  end

  it "preserves metric totals and trends when only the cache events (stability) query fails" do
    now = Time.current
    SolidObserver::CacheMetric.create!(
      event_type: "cache_read",
      period_start: now.beginning_of_minute,
      operations_count: 100,
      hits_count: 70,
      misses_count: 30,
      errors_count: 5,
      duration_total: 12.5
    )

    allow(SolidObserver::CacheEvent).to receive(:where).and_raise(
      ActiveRecord::StatementInvalid.new("no such table: solid_observer_cache_events")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats).not_to have_key(:error)
    expect(stats[:operations_count]).to eq(100)
    expect(stats[:hits_count]).to eq(70)
    expect(stats[:hit_rate]).to be > 0.0
    expect(stats[:throughput]).to be > 0.0
    expect(stats[:stability]).to include(available: false, state: :stable)
  end

  it "sanitizes non-ActiveRecord errors in fallback" do
    allow(SolidObserver::CacheMetric).to receive(:where).and_raise(
      TypeError.new("no implicit conversion of nil into String")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:error]).to eq("Service temporarily unavailable")
  end

  it "sanitizes generic RuntimeError in fallback without leaking message" do
    allow(SolidObserver::CacheMetric).to receive(:where).and_raise(
      RuntimeError.new("PG::DuplicateTable: relation \"cache_entries\" already exists")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:error]).to eq("Service temporarily unavailable")
  end
end
