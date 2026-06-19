# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CableMetric do
  before(:all) do
    connection = described_class.connection
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

  before { described_class.delete_all }

  it "inherits from BaseRecord" do
    expect(described_class.superclass).to eq(SolidObserver::BaseRecord)
  end

  it "uses solid_observer_cable_metrics table" do
    expect(described_class.table_name).to eq("solid_observer_cable_metrics")
  end

  it "validates required fields" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors[:period_start]).to be_present
  end
end
