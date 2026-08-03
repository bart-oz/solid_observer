# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Queries::TraceQuery do
  before(:all) do
    reset_trace_tables
  end

  after do
    SolidObserver.reset_configuration!
  end

  before do
    SolidObserver::QueueEvent.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all
  end

  describe "#call" do
    context "with no matching events" do
      it "returns an empty result" do
        result = described_class.new.call(correlation_id: "no-such-id")

        expect(result.rows).to be_empty
        expect(result.unavailable_components).to be_empty
      end
    end

    context "with events from all enabled components" do
      before do
        enable_cache_and_cable
      end

      let(:shared_time) { Time.utc(2026, 1, 1, 12, 0, 0) }

      it "returns rows sorted by time and component priority" do
        create_queue_event(correlation_id: "shared", recorded_at: shared_time, job_class: "AJob", queue_name: "default", duration: 1.0)
        create_cache_event(correlation_id: "shared", recorded_at: shared_time, key_digest: "abc", hit: true, duration: 0.5)
        create_cable_event(correlation_id: "shared", recorded_at: shared_time, channel_class: "ChatChannel", broadcasting_digest: "dig", duration: 0.2)

        result = described_class.new.call(correlation_id: "shared")

        expect(result.rows.size).to eq(3)
        expect(result.rows.map { |row| row[:component] }).to eq([:queue, :cache, :cable])
        expect(result.unavailable_components).to be_empty
      end
    end

    context "with different recorded_at times" do
      it "returns rows in ascending time order" do
        create_queue_event(correlation_id: "time", recorded_at: Time.utc(2026, 1, 1, 12, 0, 2), duration: 1.0)
        create_queue_event(correlation_id: "time", recorded_at: Time.utc(2026, 1, 1, 12, 0, 1), duration: 1.0)
        create_queue_event(correlation_id: "time", recorded_at: Time.utc(2026, 1, 1, 12, 0, 3), duration: 1.0)

        result = described_class.new.call(correlation_id: "time")

        expect(result.rows.map { |row| row[:recorded_at] }).to eq([
          Time.utc(2026, 1, 1, 12, 0, 1),
          Time.utc(2026, 1, 1, 12, 0, 2),
          Time.utc(2026, 1, 1, 12, 0, 3)
        ])
      end
    end

    context "with a total limit" do
      let(:base_time) { Time.utc(2026, 1, 1, 12, 0, 0) }

      it "defaults to 100 rows and keeps the most recent" do
        120.times do |i|
          create_queue_event(correlation_id: "limited", recorded_at: base_time + i, duration: 1.0)
        end

        result = described_class.new.call(correlation_id: "limited")

        expect(result.rows.size).to eq(100)
        expect(result.rows.first[:recorded_at]).to eq(base_time + 20)
        expect(result.rows.last[:recorded_at]).to eq(base_time + 119)
      end

      it "uses a positive requested limit" do
        10.times do |i|
          create_queue_event(correlation_id: "limited", recorded_at: base_time + i, duration: 1.0)
        end

        result = described_class.new.call(correlation_id: "limited", limit: 5)

        expect(result.rows.size).to eq(5)
        expect(result.rows.first[:recorded_at]).to eq(base_time + 5)
        expect(result.rows.last[:recorded_at]).to eq(base_time + 9)
      end

      it "falls back to the default limit when limit is non-positive" do
        120.times do |i|
          create_queue_event(correlation_id: "limited", recorded_at: base_time + i, duration: 1.0)
        end

        result = described_class.new.call(correlation_id: "limited", limit: 0)

        expect(result.rows.size).to eq(100)
      end
    end

    context "with cable broadcast collapse" do
      before do
        enable_cache_and_cable
      end

      let(:base_time) { Time.utc(2026, 1, 1, 12, 0, 0) }

      it "collapses consecutive broadcasts with the same nonblank digest" do
        3.times do |i|
          create_cable_event(correlation_id: "collapse", recorded_at: base_time + i, event_type: "broadcast", broadcasting_digest: "shared-digest", duration: 0.1)
        end
        create_cable_event(correlation_id: "collapse", recorded_at: base_time + 3, event_type: "transmit_subscription_rejection", channel_class: "ChatChannel", duration: 0.1)
        2.times do |i|
          create_cable_event(correlation_id: "collapse", recorded_at: base_time + 4 + i, event_type: "broadcast", broadcasting_digest: "shared-digest", duration: 0.1)
        end

        result = described_class.new.call(correlation_id: "collapse")

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(3)
        broadcast_rows = cable_rows.select { |row| row[:event_type] == "broadcast" }
        expect(broadcast_rows[0][:collapsed_count]).to eq(3)
        expect(broadcast_rows[1][:collapsed_count]).to eq(2)
      end

      it "does not collapse broadcasts with different digests" do
        create_cable_event(correlation_id: "diff", recorded_at: base_time, event_type: "broadcast", broadcasting_digest: "d1", duration: 0.1)
        create_cable_event(correlation_id: "diff", recorded_at: base_time + 1, event_type: "broadcast", broadcasting_digest: "d2", duration: 0.1)

        result = described_class.new.call(correlation_id: "diff")

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(2)
        expect(cable_rows).to all(satisfy { |row| row[:collapsed_count].nil? })
      end

      it "does not collapse non-broadcast cable events" do
        create_cable_event(correlation_id: "rej", recorded_at: base_time, event_type: "transmit_subscription_rejection", channel_class: "ChatChannel", duration: 0.1)
        create_cable_event(correlation_id: "rej", recorded_at: base_time + 1, event_type: "transmit_subscription_rejection", channel_class: "ChatChannel", duration: 0.1)

        result = described_class.new.call(correlation_id: "rej")

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(2)
        expect(cable_rows).to all(satisfy { |row| row[:collapsed_count].nil? })
      end
    end

    context "with the cable cap" do
      before do
        enable_cache_and_cable
      end

      let(:base_time) { Time.utc(2026, 1, 1, 12, 0, 0) }

      it "caps collapsed cable rows to 49 plus one summary row" do
        60.times do |i|
          create_cable_event(correlation_id: "cap", recorded_at: base_time + i, event_type: "broadcast", broadcasting_digest: "digest-#{i}", duration: 0.1)
        end

        result = described_class.new.call(correlation_id: "cap")

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(50)
        summary_row = cable_rows.find { |row| row[:event_type] == "cable_summary" }
        expect(summary_row).not_to be_nil
        expect(summary_row[:collapsed_count]).to eq(11)
      end

      it "does not cap when collapsed rows are within the limit" do
        60.times do |i|
          create_cable_event(correlation_id: "no-cap", recorded_at: base_time + i, event_type: "broadcast", broadcasting_digest: "same-digest", duration: 0.1)
        end

        result = described_class.new.call(correlation_id: "no-cap")

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(1)
        expect(cable_rows.first[:collapsed_count]).to eq(60)
      end

      it "keeps the overflow summary in the newest total window" do
        100.times do |i|
          create_queue_event(correlation_id: "window", recorded_at: base_time + i, duration: 1.0)
        end
        55.times do |i|
          create_cable_event(correlation_id: "window", recorded_at: base_time + 100 + i, event_type: "broadcast", broadcasting_digest: "digest-#{i}", duration: 0.1)
        end

        result = described_class.new.call(correlation_id: "window", limit: 100)

        cable_rows = result.rows.select { |row| row[:component] == :cable }
        expect(cable_rows.size).to eq(50)
        summary_row = cable_rows.find { |row| row[:event_type] == "cable_summary" }
        expect(summary_row).not_to be_nil
        expect(summary_row[:collapsed_count]).to eq(6)
        expect(summary_row[:recorded_at]).to eq(base_time + 105)
      end
    end

    context "with disabled components" do
      it "skips components that are not enabled" do
        create_cache_event(correlation_id: "disabled", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), key_digest: "k", duration: 0.5)
        create_cable_event(correlation_id: "disabled", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 0.1)

        result = described_class.new.call(correlation_id: "disabled")

        expect(result.rows).to be_empty
        expect(result.unavailable_components).to be_empty
      end
    end

    context "with an unavailable component" do
      before do
        enable_cache_and_cable
      end

      it "reports a component whose table is not reachable" do
        create_queue_event(correlation_id: "unavailable", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 1.0)
        create_cable_event(correlation_id: "unavailable", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 0.1)

        bad_connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, data_source_exists?: false)
        allow(SolidObserver::CacheEvent).to receive(:connection).and_return(bad_connection)

        result = described_class.new.call(correlation_id: "unavailable")

        expect(result.unavailable_components).to include(:cache)
        expect(result.rows.map { |row| row[:component] }).to contain_exactly(:queue, :cable)
      end

      it "rescues connection errors and preserves other components" do
        create_queue_event(correlation_id: "error", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 1.0)
        create_cable_event(correlation_id: "error", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 0.1)

        bad_connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
        allow(bad_connection).to receive(:data_source_exists?).and_raise(ActiveRecord::ConnectionNotEstablished)
        allow(SolidObserver::CacheEvent).to receive(:connection).and_return(bad_connection)

        result = described_class.new.call(correlation_id: "error")

        expect(result.unavailable_components).to include(:cache)
        expect(result.rows.map { |row| row[:component] }).to contain_exactly(:queue, :cable)
      end
    end

    context "with PII-sensitive data" do
      before do
        enable_cache_and_cable
      end

      it "excludes unsafe columns from returned rows and scopes assertions by component" do
        create_queue_event(correlation_id: "pii", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), duration: 1.0)
        create_cache_event(correlation_id: "pii", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), key_digest: "secret-key", hit: true, duration: 0.5)
        create_cable_event(correlation_id: "pii", recorded_at: Time.utc(2026, 1, 1, 12, 0, 0), broadcasting_digest: "secret-broadcast", duration: 0.1)

        result = described_class.new.call(correlation_id: "pii")

        cache_rows = result.rows.select { |row| row[:component] == :cache }
        cable_rows = result.rows.select { |row| row[:component] == :cable }

        expect(cache_rows).not_to be_empty
        expect(cable_rows).not_to be_empty

        cache_rows.each { |row| expect(row).not_to have_key(:key_digest) }
        cable_rows.each { |row| expect(row).not_to have_key(:broadcasting_digest) }

        result.rows.each do |row|
          expect(row).not_to have_key(:error_message)
          expect(row).not_to have_key(:metadata)
        end
      end
    end

    context "with error_class present" do
      before do
        enable_cache_and_cable
      end

      let(:base_time) { Time.utc(2026, 1, 1, 12, 0, 0) }

      it "includes error_class for cache and cable rows" do
        create_cache_event(correlation_id: "errors", recorded_at: base_time, key_digest: "k", event_type: "cache_error", error_class: "Redis::TimeoutError", duration: 0.5)
        create_cable_event(correlation_id: "errors", recorded_at: base_time + 1, event_type: "transmit_subscription_rejection", channel_class: "ChatChannel", error_class: "ActionCableError", duration: 0.2)

        result = described_class.new.call(correlation_id: "errors")

        cache_row = result.rows.find { |row| row[:component] == :cache }
        cable_row = result.rows.find { |row| row[:component] == :cable }

        expect(cache_row[:error_class]).to eq("Redis::TimeoutError")
        expect(cable_row[:error_class]).to eq("ActionCableError")
      end
    end
  end

  def reset_trace_tables
    connection = SolidObserver::BaseRecord.connection
    reset_table(connection, :solid_observer_queue_events) do |t|
      t.string :event_type, null: false
      t.string :job_class
      t.string :queue_name
      t.float :duration
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
    reset_table(connection, :solid_observer_cache_events) do |t|
      t.string :event_type, null: false
      t.string :key_digest, null: false
      t.boolean :hit
      t.float :duration
      t.string :error_class
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
    reset_table(connection, :solid_observer_cable_events) do |t|
      t.string :event_type, null: false
      t.string :channel_class
      t.string :broadcasting_digest
      t.float :duration
      t.string :error_class
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
    SolidObserver::QueueEvent.reset_column_information
    SolidObserver::CacheEvent.reset_column_information
    SolidObserver::CableEvent.reset_column_information
  end

  def reset_table(connection, table, &block)
    connection.drop_table(table, if_exists: true)
    connection.create_table(table, &block)
  end

  def enable_cache_and_cable
    SolidObserver.config.observe_cache = true
    SolidObserver.config.observe_cable = true
    stub_const("SolidCache", Module.new)
    stub_const("SolidCable", Module.new)
  end

  def create_queue_event(correlation_id:, recorded_at:, event_type: "job_completed", job_class: nil, queue_name: nil, duration: nil)
    SolidObserver::QueueEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      job_class: job_class,
      queue_name: queue_name,
      duration: duration
    )
  end

  def create_cache_event(correlation_id:, recorded_at:, key_digest:, event_type: "cache_hit", hit: nil, error_class: nil, duration: nil)
    SolidObserver::CacheEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      key_digest: key_digest,
      hit: hit,
      error_class: error_class,
      duration: duration
    )
  end

  def create_cable_event(correlation_id:, recorded_at:, event_type: "broadcast", channel_class: nil, broadcasting_digest: nil, error_class: nil, duration: nil)
    SolidObserver::CableEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      channel_class: channel_class,
      broadcasting_digest: broadcasting_digest,
      error_class: error_class,
      duration: duration
    )
  end
end
