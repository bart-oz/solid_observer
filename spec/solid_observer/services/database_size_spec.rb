# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::DatabaseSize do
  let(:logger) { instance_double(Logger, warn: nil) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  describe ".call" do
    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter, adapter_name: adapter_name) }
    let(:adapter_name) { "SQLite" }

    it "returns sqlite size via pragma query" do
      allow(connection).to receive(:query_value)
        .with("SELECT pragma_page_count() * pragma_page_size()")
        .and_return(4_096_000)

      result = described_class.call(connection: connection)

      expect(result).to eq(4_096_000)
    end

    it "returns postgresql table size as integer bytes" do
      allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value)
        .with("SELECT pg_total_relation_size('solid_observer_queue_events')")
        .and_return("134217728")

      result = described_class.call(connection: connection)

      expect(result).to eq(134_217_728)
    end

    it "treats PostGIS as postgresql" do
      allow(connection).to receive(:adapter_name).and_return("PostGIS")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value)
        .with("SELECT pg_total_relation_size('solid_observer_queue_events')")
        .and_return(1024)

      result = described_class.call(connection: connection)

      expect(result).to eq(1024)
    end

    it "returns mysql2 table size from information_schema" do
      allow(connection).to receive(:adapter_name).and_return("Mysql2")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value)
        .with(
          a_string_including(
            "information_schema.tables",
            "table_schema = DATABASE()",
            "table_name = 'solid_observer_queue_events'"
          )
        )
        .and_return(67_108_864)

      result = described_class.call(connection: connection)

      expect(result).to eq(67_108_864)
    end

    it "returns trilogy table size from information_schema" do
      allow(connection).to receive(:adapter_name).and_return("Trilogy")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value)
        .with(a_string_including("information_schema.tables"))
        .and_return(12_345)

      result = described_class.call(connection: connection)

      expect(result).to eq(12_345)
    end

    it "returns nil and logs one warning for unknown adapter" do
      allow(connection).to receive(:adapter_name).and_return("Oracle")

      expect(connection).not_to receive(:query_value)
      expect(logger).to receive(:warn).with(/Unknown adapter for DatabaseSize: "Oracle"/).once

      result = described_class.call(connection: connection)

      expect(result).to be_nil
    end

    it "rescues StatementInvalid and returns nil" do
      allow(connection).to receive(:adapter_name).and_return("PostgreSQL")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value).and_raise(ActiveRecord::StatementInvalid.new("boom"))

      expect(logger).to receive(:warn).with(/DatabaseSize query failed: boom/)

      result = described_class.call(connection: connection)

      expect(result).to be_nil
    end

    it "rescues ConnectionNotEstablished and returns nil" do
      allow(connection).to receive(:query_value).and_raise(ActiveRecord::ConnectionNotEstablished.new("offline"))

      expect(logger).to receive(:warn).with(/DatabaseSize query failed: offline/)

      result = described_class.call(connection: connection)

      expect(result).to be_nil
    end

    it "returns nil when adapter query_value returns nil" do
      allow(connection).to receive(:adapter_name).and_return("Mysql2")
      allow(connection).to receive(:quote).with("solid_observer_queue_events").and_return("'solid_observer_queue_events'")
      allow(connection).to receive(:query_value).and_return(nil)

      result = described_class.call(connection: connection)

      expect(result).to be_nil
    end

    it "does not rescue NoMethodError" do
      bad_connection = Object.new

      expect { described_class.call(connection: bad_connection) }.to raise_error(NoMethodError)
    end
  end
end
