# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::StorageInfo do
  before(:all) do
    connection = described_class.connection

    unless connection.table_exists?(:solid_observer_storage_info)
      connection.create_table :solid_observer_storage_info do |t|
        t.bigint :db_size_bytes, null: false
        t.bigint :event_count, null: false
        t.datetime :recorded_at, null: false
        t.string :component, null: false, default: "queue_observer"

        t.index :recorded_at
        t.index :component
      end
    end

    next if connection.column_exists?(:solid_observer_storage_info, :component)

    connection.add_column :solid_observer_storage_info, :component, :string, null: false, default: "queue_observer"
    connection.add_index :solid_observer_storage_info, :component unless connection.index_exists?(:solid_observer_storage_info, :component)
  end

  before { described_class.delete_all }

  it "inherits from BaseEvent" do
    expect(described_class.superclass).to eq(SolidObserver::BaseEvent)
  end

  it "is not abstract (can be instantiated)" do
    expect(described_class.abstract_class?).to be false
  end

  it "uses solid_observer_storage_info table" do
    expect(described_class.table_name).to eq("solid_observer_storage_info")
  end

  it "has validations defined" do
    expect(described_class.validators.map(&:class)).to include(ActiveRecord::Validations::PresenceValidator)
  end

  it "defines recent scope" do
    expect(described_class).to respond_to(:recent)
  end

  it "defines since scope" do
    expect(described_class).to respond_to(:since)
  end

  it "defines record_snapshot class method" do
    expect(described_class).to respond_to(:record_snapshot)
  end

  it "defines db_size_mb instance method" do
    expect(described_class.instance_methods).to include(:db_size_mb)
  end

  it "defines db_size_gb instance method" do
    expect(described_class.instance_methods).to include(:db_size_gb)
  end

  describe ".record_snapshot" do
    it "persists the default queue_observer component" do
      snapshot = described_class.record_snapshot(db_size: 1024, event_count: 5)

      expect(snapshot).to have_attributes(
        component: "queue_observer",
        db_size_bytes: 1024,
        event_count: 5
      )
      expect(snapshot).to be_persisted
    end

    it "persists an explicit component" do
      snapshot = described_class.record_snapshot(db_size: 2048, event_count: 10, component: "cache_observer")

      expect(snapshot).to have_attributes(
        component: "cache_observer",
        db_size_bytes: 2048,
        event_count: 10
      )
    end

    it "persists a solid_cable component" do
      snapshot = described_class.record_snapshot(db_size: 1024, event_count: 5, component: "solid_cable")

      expect(snapshot).to have_attributes(
        component: "solid_cable",
        db_size_bytes: 1024,
        event_count: 5
      )
    end

    it "persists a cable_observer component" do
      snapshot = described_class.record_snapshot(db_size: 2048, event_count: 10, component: "cable_observer")

      expect(snapshot).to have_attributes(
        component: "cable_observer",
        db_size_bytes: 2048,
        event_count: 10
      )
    end

    it "logs and re-raises validation failures" do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)

      expect {
        described_class.record_snapshot(db_size: -1, event_count: -2)
      }.to raise_error(ActiveRecord::RecordInvalid)

      expect(logger).to have_received(:error).with(
        a_string_including("[SolidObserver] Failed to record storage snapshot: Validation failed:")
      )
      expect(described_class.count).to eq(0)
    end
  end

  describe "#db_size_mb" do
    it "converts bytes to megabytes" do
      snapshot = described_class.new(db_size_bytes: 10_485_760)

      expect(snapshot.db_size_mb).to eq(10.0)
    end
  end

  describe "#db_size_gb" do
    it "converts bytes to gigabytes" do
      snapshot = described_class.new(db_size_bytes: 1_073_741_824)

      expect(snapshot.db_size_gb).to eq(1.0)
    end
  end
end
