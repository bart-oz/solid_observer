# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CacheMetric do
  before(:all) do
    connection = described_class.connection
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

  before { described_class.delete_all }

  it "inherits from BaseRecord" do
    expect(described_class.superclass).to eq(SolidObserver::BaseRecord)
  end

  it "uses solid_observer_cache_metrics table" do
    expect(described_class.table_name).to eq("solid_observer_cache_metrics")
  end

  it "validates required fields" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors[:event_type]).to be_present
    expect(record.errors[:period_start]).to be_present
  end
end
