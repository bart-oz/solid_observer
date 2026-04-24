# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Engine do
  let(:logger) { instance_double(Logger, warn: nil, info: nil) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  it "is a Rails::Engine" do
    expect(described_class.ancestors).to include(Rails::Engine)
  end

  it "isolates namespace to SolidObserver" do
    expect(described_class.isolated?).to be true
  end

  describe ".check_solid_queue_availability" do
    it "warns when SolidQueue is not defined" do
      hide_const("SolidQueue")

      expect(logger).to receive(:warn).with(/SolidQueue not detected/)

      described_class.check_solid_queue_availability
    end

    it "does not warn when SolidQueue is defined" do
      stub_const("SolidQueue", Class.new)

      expect(logger).not_to receive(:warn)

      described_class.check_solid_queue_availability
    end
  end

  describe ".activate_subscribers" do
    let(:pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool) }
    let(:cache) { instance_double(ActiveRecord::ConnectionAdapters::SchemaCache) }
    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

    before do
      allow(SolidObserver::BaseEvent).to receive(:connection_pool).and_return(pool)
      allow(pool).to receive(:schema_cache).and_return(cache)
      allow(pool).to receive(:with_connection).and_yield(connection)
      allow(cache).to receive(:data_source_exists?).and_return(false)
      allow(connection).to receive(:data_source_exists?).and_return(true)
      allow(SolidObserver::Subscriber).to receive(:subscribe!)
    end

    after { SolidObserver.reset_configuration! }

    it "subscribes in realtime mode without checking database tables" do
      SolidObserver.config.storage_mode = :realtime

      expect(logger).to receive(:info).with(/real-time mode/)
      expect(SolidObserver::Subscriber).to receive(:subscribe!)
      expect(pool).not_to receive(:schema_cache)
      expect(pool).not_to receive(:with_connection)

      described_class.activate_subscribers
    end

    it "uses schema cache fast path and subscribes without opening a connection" do
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_queue_events").and_return(true)

      described_class.activate_subscribers

      expect(cache).to have_received(:data_source_exists?).with(pool, "solid_observer_queue_events")
      expect(pool).not_to have_received(:with_connection)
      expect(SolidObserver::Subscriber).to have_received(:subscribe!)
    end

    it "subscribes when table exists via slow path" do
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_queue_events").and_return(false)
      allow(connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(true)

      expect(SolidObserver::Subscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "logs migration instruction and does not subscribe when table is absent" do
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_queue_events").and_return(false)
      allow(connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(false)

      expect(logger).to receive(:info).with(/Tables not found/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles ActiveRecord::NoDatabaseError by skipping activation" do
      allow(pool).to receive(:with_connection).and_raise(ActiveRecord::NoDatabaseError)

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles ActiveRecord::ConnectionNotEstablished by skipping activation" do
      allow(pool).to receive(:with_connection).and_raise(ActiveRecord::ConnectionNotEstablished)

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles ActiveRecord::StatementInvalid by skipping activation" do
      allow(pool).to receive(:with_connection).and_raise(ActiveRecord::StatementInvalid.new("boom"))

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles PG::ConnectionBad by skipping activation" do
      stub_const("PG::ConnectionBad", Class.new(StandardError))
      allow(pool).to receive(:with_connection).and_raise(PG::ConnectionBad)

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles Mysql2::Error::ConnectionError by skipping activation" do
      stub_const("Mysql2::Error::ConnectionError", Class.new(StandardError))
      allow(pool).to receive(:with_connection).and_raise(Mysql2::Error::ConnectionError)

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "handles SQLite3::CantOpenException by skipping activation" do
      stub_const("SQLite3::CantOpenException", Class.new(StandardError))
      allow(pool).to receive(:with_connection).and_raise(SQLite3::CantOpenException)

      expect(logger).to receive(:info).with(/not reachable/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "uses BaseEvent connection pool and never uses ActiveRecord::Base connection APIs" do
      expect(SolidObserver::BaseEvent).to receive(:connection_pool).and_return(pool)
      expect(ActiveRecord::Base).not_to receive(:connection)
      expect(ActiveRecord::Base).not_to receive(:connection_pool)
      expect(SolidObserver::Subscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end
  end

  describe "routes" do
    it "has a route set" do
      expect(described_class.routes).to be_a(ActionDispatch::Routing::RouteSet)
    end
  end

  describe "configuration" do
    it "activates subscribers after initialization" do
      expect(described_class).to respond_to(:activate_subscribers)
    end
  end
end
