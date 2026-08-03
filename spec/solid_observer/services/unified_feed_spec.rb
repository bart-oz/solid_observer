# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::UnifiedFeed do
  let(:config) { SolidObserver.config }

  before(:all) do
    connection = SolidObserver::QueueEvent.connection

    unless connection.table_exists?(:solid_observer_queue_events)
      connection.create_table :solid_observer_queue_events do |t|
        t.string :event_type, null: false, limit: 50
        t.string :job_class, limit: 100
        t.string :queue_name, limit: 50
        t.float :duration
        t.text :metadata
        t.string :correlation_id, limit: 64
        t.datetime :recorded_at, null: false
      end
    end

    cache_connection = SolidObserver::CacheEvent.connection
    unless cache_connection.table_exists?(:solid_observer_cache_events)
      cache_connection.create_table :solid_observer_cache_events do |t|
        t.string :event_type, null: false, limit: 64
        t.string :key_digest, null: false, limit: 64
        t.boolean :hit
        t.float :duration
        t.string :error_class, limit: 255
        t.text :error_message
        t.text :metadata
        t.string :correlation_id, limit: 64
        t.datetime :recorded_at, null: false
      end
    end

    cable_connection = SolidObserver::CableEvent.connection
    unless cable_connection.table_exists?(:solid_observer_cable_events)
      cable_connection.create_table :solid_observer_cable_events do |t|
        t.string :event_type, null: false, limit: 64
        t.string :channel_class, limit: 255
        t.string :broadcasting_digest, limit: 64
        t.float :duration
        t.string :error_class, limit: 255
        t.text :error_message
        t.text :metadata
        t.string :correlation_id, limit: 64
        t.datetime :recorded_at, null: false
      end
    end
    SolidObserver::QueueEvent.reset_column_information
    SolidObserver::CacheEvent.reset_column_information
    SolidObserver::CableEvent.reset_column_information
  end

  before do
    config.storage_mode = :persistence
    config.observe_queue = true
    config.observe_cache = true
    config.observe_cable = true
    allow(config).to receive(:solid_cache_available?).and_return(true)
    allow(config).to receive(:solid_cable_available?).and_return(true)
    SolidObserver::QueueEvent.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all
  end

  after { SolidObserver.reset_configuration! }

  describe ".call" do
    context "in realtime mode" do
      before { config.storage_mode = :realtime }

      it "returns empty array" do
        expect(described_class.call).to eq([])
      end
    end

    context "in persistence mode" do
      it "returns empty array when no events exist" do
        expect(described_class.call).to eq([])
      end

      it "merges queue events" do
        SolidObserver::QueueEvent.create!(
          event_type: "job_completed",
          job_class: "TestJob",
          queue_name: "default",
          recorded_at: 1.minute.ago
        )

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:queue)
        expect(result[0][:event_type]).to eq("job_completed")
        expect(result[0][:detail]).to eq("TestJob · default")
      end

      it "merges cache events" do
        SolidObserver::CacheEvent.create!(
          event_type: "cache_hit",
          key_digest: "abc123def456ghi",
          recorded_at: 2.minutes.ago
        )

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:cache)
        expect(result[0][:detail]).to eq("abc123def4…")
      end

      it "merges cable events" do
        SolidObserver::CableEvent.create!(
          event_type: "message_broadcast",
          channel_class: "ChatChannel",
          recorded_at: 3.minutes.ago
        )

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:cable)
        expect(result[0][:detail]).to eq("ChatChannel")
      end

      it "sorts by recorded_at descending and caps at limit" do
        SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 1.minute.ago)
        SolidObserver::QueueEvent.create!(event_type: "job_enqueued", recorded_at: 30.seconds.ago)
        SolidObserver::CacheEvent.create!(event_type: "cache_hit", key_digest: "key1", recorded_at: 2.minutes.ago)

        result = described_class.call(limit: 2)
        expect(result.size).to eq(2)
        expect(result[0][:recorded_at]).to be >= result[1][:recorded_at]
      end

      it "skips disabled components" do
        config.observe_cache = false
        config.observe_cable = false

        SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 1.minute.ago)
        SolidObserver::CacheEvent.create!(event_type: "cache_hit", key_digest: "key1", recorded_at: 1.minute.ago)

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:queue)
      end

      it "includes correlation_id when present" do
        SolidObserver::QueueEvent.create!(
          event_type: "job_completed",
          correlation_id: "abc-123",
          recorded_at: 1.minute.ago
        )

        result = described_class.call
        expect(result[0][:correlation_id]).to eq("abc-123")
      end

      it "includes error_class when present" do
        SolidObserver::CacheEvent.create!(
          event_type: "cache_error",
          key_digest: "key1",
          error_class: "RuntimeError",
          recorded_at: 1.minute.ago
        )

        result = described_class.call
        expect(result[0][:error_class]).to eq("RuntimeError")
      end

      it "isolates queue errors without blanking other sources" do
        allow(SolidObserver::QueueEvent).to receive(:recent).and_raise(ActiveRecord::StatementInvalid, "test error")
        SolidObserver::CacheEvent.create!(event_type: "cache_hit", key_digest: "key1", recorded_at: 1.minute.ago)

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:cache)
      end

      it "isolates cache errors without blanking other sources" do
        allow(SolidObserver::CacheEvent).to receive(:recent).and_raise(ActiveRecord::StatementInvalid, "test error")
        SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 1.minute.ago)

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:queue)
      end

      it "isolates cable errors without blanking other sources" do
        allow(SolidObserver::CableEvent).to receive(:recent).and_raise(ActiveRecord::StatementInvalid, "test error")
        SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 1.minute.ago)

        result = described_class.call
        expect(result.size).to eq(1)
        expect(result[0][:component]).to eq(:queue)
      end
    end
  end

  describe "privacy" do
    it "never includes error_message in normalized rows" do
      SolidObserver::CacheEvent.create!(
        event_type: "cache_error",
        key_digest: "key1",
        error_class: "RuntimeError",
        error_message: "SECRET SHOULD NOT APPEAR",
        recorded_at: 1.minute.ago
      )

      result = described_class.call
      result.each do |row|
        expect(row).not_to have_key(:error_message)
        expect(row.values.join).not_to include("SECRET SHOULD NOT APPEAR")
      end
    end

    it "never includes metadata in normalized rows" do
      SolidObserver::QueueEvent.create!(
        event_type: "job_completed",
        metadata: '{"secret": true}',
        recorded_at: 1.minute.ago
      )

      result = described_class.call
      result.each do |row|
        expect(row).not_to have_key(:metadata)
      end
    end

    it "never includes raw key values or payloads" do
      SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 1.minute.ago)

      result = described_class.call
      result.each do |row|
        expect(row.keys).to match_array([:component, :event_type, :recorded_at, :detail, :correlation_id, :error_class])
      end
    end

    it "uses key_digest (truncated) not raw key for cache detail" do
      SolidObserver::CacheEvent.create!(
        event_type: "cache_hit",
        key_digest: "very_long_digest_that_should_be_truncated",
        recorded_at: 1.minute.ago
      )

      result = described_class.call
      expect(result[0][:detail]).to eq("very_long_…")
      expect(result[0][:detail]).not_to include("that_should_be_truncated")
    end
  end
end
