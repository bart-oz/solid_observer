# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/solid_observer/services/record_cache_metric"
require "time"

RSpec.describe SolidObserver::Services::RecordCacheMetric do
  let(:event_name) { "cache_read.active_support" }
  let(:started_at) { Time.current }
  let(:finished_at) { started_at + 0.01 }
  let(:payload) { {hit: true} }
  let(:event) { ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", payload) }

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

  it "records a metric in a 1-minute bucket" do
    travel_to(Time.parse("2026-06-01 12:34:45 UTC")) do
      described_class.call(event: event)

      metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read")
      expect(metric.period_start).to eq(Time.parse("2026-06-01 12:34:00 UTC"))
      expect(metric.operations_count).to eq(1)
      expect(metric.hits_count).to eq(1)
      expect(metric.misses_count).to eq(0)
      expect(metric.errors_count).to eq(0)
      expect(metric.duration_total).to be > 0
    end
  end

  it "tracks miss using explicit payload hit false" do
    miss_event = ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", {hit: false})

    described_class.call(event: miss_event)

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read")
    expect(metric.operations_count).to eq(1)
    expect(metric.hits_count).to eq(0)
    expect(metric.misses_count).to eq(1)
  end

  it "tracks errors using explicit exception payload" do
    error_event = ActiveSupport::Notifications::Event.new(event_name, started_at, finished_at, "id", {exception: ["RuntimeError", "boom"]})

    described_class.call(event: error_event)

    metric = SolidObserver::CacheMetric.find_by!(event_type: "cache_read")
    expect(metric.errors_count).to eq(1)
  end
end
