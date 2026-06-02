# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/solid_observer/services/cache_stats"

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

  before { SolidObserver::CacheMetric.delete_all }

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
    expect(stats[:error]).to eq("missing table")
  end
end
