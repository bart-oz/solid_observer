# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::CleanupStorage do
  let(:logger) { instance_double(Logger, info: nil, warn: nil, error: nil) }
  let(:relation) { instance_double(ActiveRecord::Relation) }
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }
  let(:db_config) { instance_double(ActiveRecord::DatabaseConfigurations::HashConfig, database: "/tmp/test.sqlite3") }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
    allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)
    allow(SolidObserver.config).to receive(:max_db_size).and_return(1.megabyte)
    allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.8)

    allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
    allow(SolidObserver::QueueEvent).to receive(:where).and_return(relation)
    allow(SolidObserver::QueueEvent).to receive(:count).and_return(500)
    allow(SolidObserver::QueueEvent).to receive(:connection).and_return(connection)
    allow(SolidObserver::QueueEvent).to receive(:connection_db_config).and_return(db_config)

    allow(relation).to receive(:delete_all).and_return(10)
    allow(connection).to receive(:execute)
    allow(connection).to receive(:adapter_name).and_return("SQLite")

    allow(SolidObserver::StorageInfo).to receive(:record_snapshot)
    allow(File).to receive(:exist?).and_return(true)
    allow(File).to receive(:size).and_return(500.kilobytes)
  end

  describe ".call" do
    it "deletes events older than retention period" do
      expect(relation).to receive(:delete_all)

      described_class.call
    end

    it "returns count of deleted events" do
      allow(relation).to receive(:delete_all).and_return(15)

      result = described_class.call

      expect(result).to eq(15)
    end

    it "records snapshot within transaction" do
      expect(SolidObserver::StorageInfo).to receive(:record_snapshot).with(
        hash_including(:db_size, :event_count)
      )

      described_class.call
    end

    it "runs VACUUM after transaction" do
      expect(connection).to receive(:execute).with("VACUUM")

      described_class.call
    end

    it "logs successful cleanup" do
      allow(relation).to receive(:delete_all).and_return(10)

      expect(logger).to receive(:info).with("[SolidObserver] Cleaned 10 queue events")

      described_class.call
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
        allow(File).to receive(:size).with("/tmp/test.sqlite3").and_return(850.kilobytes)
      end

      it "logs warning" do
        expect(logger).to receive(:warn).with(/Queue DB approaching limit/)

        described_class.call
      end
    end

    context "when database size is below warning threshold" do
      before do
        allow(File).to receive(:size).with("/tmp/test.sqlite3").and_return(500.kilobytes)
      end

      it "does not log warning" do
        expect(logger).not_to receive(:warn).with(/Queue DB approaching limit/)

        described_class.call
      end
    end

    context "when cleanup fails" do
      before do
        allow(relation).to receive(:delete_all).and_raise(StandardError, "DB error")
      end

      it "logs error and re-raises" do
        expect(logger).to receive(:error).with("[SolidObserver] Cleanup failed: DB error")

        expect { described_class.call }.to raise_error(StandardError, "DB error")
      end
    end
  end

  describe "private methods" do
    let(:service) { described_class.new }

    describe "#format_bytes" do
      it "formats bytes correctly" do
        expect(service.send(:format_bytes, 0)).to eq("0 B")
        expect(service.send(:format_bytes, 1024)).to eq("1.0 KB")
        expect(service.send(:format_bytes, 1.megabyte)).to eq("1.0 MB")
        expect(service.send(:format_bytes, 1.gigabyte)).to eq("1.0 GB")
      end
    end
  end
end
