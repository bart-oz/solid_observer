# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::Services::FlushCableMetrics do
  let(:period_start) { Time.parse("2026-06-01 12:34:00 UTC") }
  let(:metrics) do
    [
      {
        period_start: period_start,
        broadcasts_count: 3,
        transmissions_count: 2,
        confirmations_count: 1,
        rejections_count: 1,
        perform_actions_count: 1,
        errors_count: 1
      }
    ]
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

  before { SolidObserver::CableMetric.delete_all }

  it "persists aggregated cable metrics" do
    expect(described_class.call(metrics)).to eq(1)

    metric = SolidObserver::CableMetric.find_by!(period_start: period_start)
    expect(metric.broadcasts_count).to eq(3)
    expect(metric.transmissions_count).to eq(2)
    expect(metric.confirmations_count).to eq(1)
    expect(metric.rejections_count).to eq(1)
    expect(metric.perform_actions_count).to eq(1)
    expect(metric.errors_count).to eq(1)
  end

  it "atomically adds later flushes to existing per-minute buckets" do
    described_class.call(metrics)
    described_class.call([
      {
        period_start: period_start,
        broadcasts_count: 2,
        transmissions_count: 1,
        confirmations_count: 0,
        rejections_count: 0,
        perform_actions_count: 0,
        errors_count: 0
      }
    ])

    metric = SolidObserver::CableMetric.find_by!(period_start: period_start)
    expect(metric.broadcasts_count).to eq(5)
    expect(metric.transmissions_count).to eq(3)
    expect(metric.confirmations_count).to eq(1)
    expect(metric.rejections_count).to eq(1)
    expect(metric.perform_actions_count).to eq(1)
    expect(metric.errors_count).to eq(1)
  end

  it "uses ActiveRecord counter arithmetic without hand-built SQL literals" do
    source = File.read(File.expand_path("../../../lib/solid_observer/services/flush_cable_metrics.rb", __dir__))

    expect(source).to include("update_counters")
    expect(source).not_to include("Arel.sql")
  end

  it "returns zero for an empty flush" do
    expect(described_class.call([])).to eq(0)
  end
end
