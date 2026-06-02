# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::StorageInfoSnapshot do
  let(:queue_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:cache_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

  before do
    allow(SolidObserver.config).to receive(:solid_queue_enabled?).and_return(true)
    allow(SolidObserver.config).to receive(:solid_cache_enabled?).and_return(true)

    allow(SolidObserver::QueueEvent).to receive(:connection).and_return(queue_connection)
    allow(SolidObserver::QueueEvent).to receive(:count).and_return(10)
    allow(queue_connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(true)

    allow(SolidObserver::CacheEvent).to receive(:connection).and_return(cache_connection)
    allow(SolidObserver::CacheEvent).to receive(:count).and_return(20)
    allow(cache_connection).to receive(:data_source_exists?).with("solid_observer_cache_events").and_return(true)

    allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: queue_connection, table_name: "solid_observer_queue_events").and_return(100)
    allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: cache_connection, table_name: "solid_observer_cache_events").and_return(200)
  end

  it "returns queue and cache component snapshots" do
    snapshots = described_class.call

    expect(snapshots.map { |item| item[:component] }).to include("queue_observer", "cache_observer")
  end

  it "omits solid cache when disabled" do
    allow(SolidObserver.config).to receive(:solid_cache_enabled?).and_return(false)

    snapshots = described_class.call

    expect(snapshots.map { |item| item[:component] }).not_to include("solid_cache")
  end

  it "omits queue observer when queue component is disabled" do
    allow(SolidObserver.config).to receive(:solid_queue_enabled?).and_return(false)

    snapshots = described_class.call

    expect(snapshots.map { |item| item[:component] }).not_to include("queue_observer")
  end

  it "reports solid cache as unavailable when gem is not loaded" do
    snapshots = described_class.call
    solid_cache = snapshots.find { |item| item[:component] == "solid_cache" }

    expect(solid_cache).to include(
      label: "SolidCache",
      available: false,
      db_size_bytes: nil,
      event_count: nil,
      record_label: "cache rows",
      recorded_at: nil,
      unavailable_reason: "SolidCache is unavailable"
    )
  end

  it "reports queue observer as unavailable when table is missing" do
    allow(queue_connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(false)

    snapshots = described_class.call
    queue_snapshot = snapshots.find { |item| item[:component] == "queue_observer" }

    expect(queue_snapshot).to include(
      available: false,
      db_size_bytes: nil,
      event_count: nil,
      unavailable_reason: "Table unavailable"
    )
  end

  it "reports queue observer as unavailable when connection raises" do
    allow(SolidObserver::QueueEvent).to receive(:connection)
      .and_raise(ActiveRecord::ConnectionNotEstablished.new("offline"))

    snapshots = described_class.call
    queue_snapshot = snapshots.find { |item| item[:component] == "queue_observer" }

    expect(queue_snapshot).to include(
      available: false,
      db_size_bytes: nil,
      event_count: nil,
      unavailable_reason: "Storage unavailable"
    )
  end
end
