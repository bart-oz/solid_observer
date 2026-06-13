# frozen_string_literal: true

require "open3"
require "spec_helper"

RSpec.describe SolidObserver::Services::StorageInfoSnapshot do
  let(:queue_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:cache_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:solid_cache_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:solid_cache_entry_class) do
    Class.new do
      class << self
        def connection
        end

        def table_name
        end

        def count
        end
      end
    end
  end
  let(:solid_cache_record_class) do
    Class.new do
      class << self
        def connection
        end

        def count
        end
      end
    end
  end

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

  it "includes Trilogy::Error in connection rescues when Trilogy is loaded before the service" do
    script = <<~RUBY
      require "active_record"
      module Trilogy
        Error = Class.new(StandardError)
      end
      require "solid_observer/services/storage_info_snapshot"

      errors = SolidObserver::Services::StorageInfoSnapshot::CONNECTION_ERRORS
      abort "Trilogy::Error missing" unless errors.include?(Trilogy::Error)
    RUBY

    project_root = File.expand_path("../../..", __dir__)
    _stdout, stderr, status = Open3.capture3(Gem.ruby, "-Ilib", "-e", script, chdir: project_root)

    expect(status).to be_success, stderr
  end

  context "when SolidCache::Entry is available" do
    before do
      allow(SolidObserver.config).to receive(:solid_queue_enabled?).and_return(false)

      stub_const("SolidCache", Module.new)
      stub_const("SolidCache::Entry", solid_cache_entry_class)
      stub_const("SolidCache::Record", solid_cache_record_class)

      allow(SolidCache::Entry).to receive(:connection).and_return(solid_cache_connection)
      allow(SolidCache::Entry).to receive(:table_name).and_return("host_app_cache_entries")
      allow(solid_cache_connection).to receive(:adapter_name).and_return("SQLite")
      allow(SolidCache::Entry).to receive(:count).and_return(7)
      allow(solid_cache_connection).to receive(:data_source_exists?).with("host_app_cache_entries").and_return(true)
      allow(SolidObserver::Services::DatabaseSize).to receive(:call)
        .with(connection: solid_cache_connection, table_name: "host_app_cache_entries")
        .and_return(300)

      allow(SolidCache::Record).to receive(:connection)
      allow(SolidCache::Record).to receive(:count)
    end

    it "uses SolidCache::Entry with its dynamic table name for storage metrics" do
      snapshots = described_class.call
      solid_cache = snapshots.find { |snapshot| snapshot[:component] == "solid_cache" }

      expect(solid_cache).to include(
        label: "SolidCache",
        available: true,
        db_size_bytes: 300,
        event_count: 7,
        record_label: "cache rows",
        unavailable_reason: nil
      )
      expect(solid_cache_connection).to have_received(:data_source_exists?).with("host_app_cache_entries")
      expect(SolidObserver::Services::DatabaseSize).to have_received(:call)
        .with(connection: solid_cache_connection, table_name: "host_app_cache_entries")
      expect(SolidCache::Record).not_to have_received(:connection)
      expect(SolidCache::Record).not_to have_received(:count)
    end

    it "uses adapter-aware approximate PostgreSQL counts for SolidCache entries" do
      allow(solid_cache_connection).to receive(:adapter_name).and_return("PostgreSQL")
      allow(solid_cache_connection).to receive(:quote).with("host_app_cache_entries").and_return("'host_app_cache_entries'")
      allow(solid_cache_connection).to receive(:query_value).and_return("1234")

      snapshots = described_class.call
      solid_cache = snapshots.find { |snapshot| snapshot[:component] == "solid_cache" }

      expect(solid_cache).to include(
        label: "SolidCache",
        available: true,
        db_size_bytes: 300,
        event_count: 1234,
        record_label: "cache rows",
        unavailable_reason: nil
      )
      expect(solid_cache_connection).to have_received(:query_value).with(/pg_class/)
      expect(SolidCache::Entry).not_to have_received(:count)
    end

    it "returns an unavailable solid cache snapshot when the concrete model raises PostgreSQL-style TypeError" do
      allow(SolidCache::Entry).to receive(:count).and_raise(TypeError, "no implicit conversion of nil into String")

      snapshots = described_class.call
      solid_cache = snapshots.find { |snapshot| snapshot[:component] == "solid_cache" }

      expect(solid_cache).to include(
        label: "SolidCache",
        available: false,
        db_size_bytes: nil,
        event_count: nil,
        record_label: "cache rows",
        recorded_at: nil,
        unavailable_reason: "Storage unavailable"
      )
    end
  end
end
