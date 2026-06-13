# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::Services::FlushCacheMetrics do
  let(:period_start) { Time.parse("2026-06-01 12:34:00 UTC") }
  let(:metrics) do
    [
      {
        event_type: "cache_read",
        period_start: period_start,
        operations_count: 3,
        hits_count: 2,
        misses_count: 1,
        errors_count: 1,
        duration_total: 0.3
      }
    ]
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

  before { SolidObserver::CacheMetric.delete_all }

  it "persists aggregated cache metrics" do
    expect(described_class.call(metrics)).to eq(1)

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read", period_start: period_start)
    expect(metric.operations_count).to eq(3)
    expect(metric.hits_count).to eq(2)
    expect(metric.misses_count).to eq(1)
    expect(metric.errors_count).to eq(1)
    expect(metric.duration_total).to be_within(0.0001).of(0.3)
  end

  it "atomically adds later flushes to existing per-minute buckets" do
    described_class.call(metrics)
    described_class.call([
      {
        event_type: "cache_read",
        period_start: period_start,
        operations_count: 2,
        hits_count: 1,
        misses_count: 1,
        errors_count: 0,
        duration_total: 0.2
      }
    ])

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read", period_start: period_start)
    expect(metric.operations_count).to eq(5)
    expect(metric.hits_count).to eq(3)
    expect(metric.misses_count).to eq(2)
    expect(metric.errors_count).to eq(1)
    expect(metric.duration_total).to be_within(0.0001).of(0.5)
  end

  it "uses ActiveRecord counter arithmetic without hand-built SQL literals" do
    source = File.read(File.expand_path("../../../lib/solid_observer/services/flush_cache_metrics.rb", __dir__))

    expect(source).to include("update_counters")
    expect(source).not_to include("Arel.sql")
  end

  it "returns zero for an empty flush" do
    expect(described_class.call([])).to eq(0)
  end
end
