# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::CleanupStorage do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:queue_relation) { instance_double(ActiveRecord::Relation) }
  let(:cache_event_relation) { instance_double(ActiveRecord::Relation) }
  let(:cache_metric_relation) { instance_double(ActiveRecord::Relation) }
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:cache_event_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:cache_metric_connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)
    allow(SolidObserver.config).to receive(:metrics_retention).and_return(90.days)
    allow(SolidObserver.config).to receive(:max_db_size).and_return(1.megabyte)
    allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.8)

    allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
    allow(SolidObserver::QueueEvent).to receive(:where).and_return(queue_relation)
    allow(SolidObserver::QueueEvent).to receive(:count).and_return(500)
    allow(SolidObserver::QueueEvent).to receive(:connection).and_return(connection)
    allow(connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(true)

    allow(SolidObserver::CacheEvent).to receive(:where).and_return(cache_event_relation)
    allow(SolidObserver::CacheEvent).to receive(:connection).and_return(cache_event_connection)
    allow(cache_event_connection).to receive(:data_source_exists?).with("solid_observer_cache_events").and_return(true)

    allow(SolidObserver::CacheMetric).to receive(:where).and_return(cache_metric_relation)
    allow(SolidObserver::CacheMetric).to receive(:connection).and_return(cache_metric_connection)
    allow(cache_metric_connection).to receive(:data_source_exists?).with("solid_observer_cache_metrics").and_return(true)

    allow(queue_relation).to receive(:delete_all).and_return(10)
    allow(cache_event_relation).to receive(:delete_all).and_return(4)
    allow(cache_metric_relation).to receive(:delete_all).and_return(3)
    allow(connection).to receive(:execute)
    allow(connection).to receive(:adapter_name).and_return("SQLite")

    allow(SolidObserver::StorageInfo).to receive(:record_snapshot)
    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return([])
    allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(500.kilobytes)
  end

  after { SolidObserver.reset_configuration! }

  describe ".call" do
    context "when in realtime mode" do
      before do
        SolidObserver.config.storage_mode = :realtime
      end

      it "returns 0 without performing cleanup" do
        result = described_class.call

        expect(result).to eq(0)
        expect(SolidObserver::QueueEvent).not_to have_received(:transaction)
      end
    end

    it "deletes events older than retention period" do
      expect(queue_relation).to receive(:delete_all)

      described_class.call
    end

    it "deletes cache events and cache metrics older than retention periods" do
      expect(cache_event_relation).to receive(:delete_all)
      expect(cache_metric_relation).to receive(:delete_all)

      described_class.call
    end

    it "returns total count of deleted telemetry rows" do
      allow(queue_relation).to receive(:delete_all).and_return(15)
      allow(cache_event_relation).to receive(:delete_all).and_return(6)
      allow(cache_metric_relation).to receive(:delete_all).and_return(2)

      result = described_class.call

      expect(result).to eq(23)
    end

    it "records snapshot within transaction" do
      expect(SolidObserver::StorageInfo).to receive(:record_snapshot).with(
        db_size: 500.kilobytes,
        event_count: 500
      )

      described_class.call
    end

    it "records additional component snapshots when available" do
      allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return([
        {component: "queue_observer", available: true, db_size_bytes: 500.kilobytes, event_count: 500},
        {component: "cache_observer", available: true, db_size_bytes: 200.kilobytes, event_count: 120}
      ])

      expect(SolidObserver::StorageInfo).to receive(:record_snapshot).with(db_size: 500.kilobytes, event_count: 500)
      expect(SolidObserver::StorageInfo).to receive(:record_snapshot).with(
        component: "cache_observer",
        db_size: 200.kilobytes,
        event_count: 120
      )

      described_class.call
    end

    it "measures DB size at most once per call" do
      expect(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).once.and_return(500.kilobytes)

      described_class.call
    end

    it "runs VACUUM after transaction" do
      expect(connection).to receive(:execute).with("VACUUM")

      described_class.call
    end

    it "logs successful cleanup" do
      allow(queue_relation).to receive(:delete_all).and_return(10)
      allow(cache_event_relation).to receive(:delete_all).and_return(4)
      allow(cache_metric_relation).to receive(:delete_all).and_return(3)

      expect(logger).to receive(:info).with(
        "[SolidObserver] Cleaned 10 queue events, 4 cache events, 3 cache metrics"
      )

      described_class.call
    end

    it "runs cache cleanup outside the queue transaction" do
      in_transaction = false

      allow(SolidObserver::QueueEvent).to receive(:transaction) do |&block|
        in_transaction = true
        block.call
      ensure
        in_transaction = false
      end

      allow(queue_relation).to receive(:delete_all) do
        expect(in_transaction).to be(true)
        10
      end
      allow(cache_event_relation).to receive(:delete_all) do
        expect(in_transaction).to be(false)
        4
      end
      allow(cache_metric_relation).to receive(:delete_all) do
        expect(in_transaction).to be(false)
        3
      end

      described_class.call
    end

    it "skips cache telemetry cleanup when cache tables are unavailable" do
      allow(cache_event_connection).to receive(:data_source_exists?).with("solid_observer_cache_events").and_return(false)
      allow(cache_metric_connection).to receive(:data_source_exists?).with("solid_observer_cache_metrics").and_return(false)

      described_class.call

      expect(cache_event_relation).not_to have_received(:delete_all)
      expect(cache_metric_relation).not_to have_received(:delete_all)
    end

    context "when VACUUM fails" do
      before do
        allow(connection).to receive(:execute).with("VACUUM").and_raise(StandardError, "VACUUM error")
      end

      it "logs warning but does not raise" do
        expect(logger).to receive(:warn).with(/Database maintenance failed/)

        expect { described_class.call }.not_to raise_error
      end
    end

    context "when database size exceeds warning threshold" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(850.kilobytes)
      end

      it "logs warning" do
        expect(logger).to receive(:warn).with(/Queue DB approaching limit/)

        described_class.call
      end
    end

    context "when database size is below warning threshold" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(500.kilobytes)
      end

      it "does not log warning" do
        expect(logger).not_to receive(:warn).with(/Queue DB approaching limit/)

        described_class.call
      end
    end

    context "when DatabaseSize returns nil" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(nil)
      end

      it "records snapshot with nil size and skips warning check" do
        expect(SolidObserver::StorageInfo).to receive(:record_snapshot).with(
          db_size: nil,
          event_count: 500
        )
        expect(logger).not_to receive(:warn).with(/Queue DB approaching limit/)

        described_class.call
      end
    end

    context "when cleanup fails" do
      before do
        allow(queue_relation).to receive(:delete_all).and_raise(StandardError, "DB error")
      end

      it "logs error and re-raises" do
        expect(logger).to receive(:error).with("[SolidObserver] Cleanup failed: DB error")

        expect { described_class.call }.to raise_error(StandardError, "DB error")
      end
    end
  end
end
