# frozen_string_literal: true

require "open3"
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

  describe "load order" do
    it "defers ActiveRecord-backed constants until ActiveRecord::Base loads" do
      script = <<~RUBY
        require "rails"
        require "active_record/railtie"
        require "solid_observer"

        abort "BaseEvent loaded too early" if SolidObserver.const_defined?(:BaseEvent, false)

        ActiveRecord::Base

        abort "BaseEvent missing" unless SolidObserver.const_defined?(:BaseEvent, false)
        abort "BaseEvent superclass mismatch" unless SolidObserver::BaseEvent < ActiveRecord::Base
      RUBY

      project_root = File.expand_path("../..", __dir__)
      _stdout, stderr, status = Open3.capture3(
        Gem.ruby, "-Ilib", "-e", script, chdir: project_root
      )

      expect(status).to be_success, stderr
    end

    it "does not define load-time availability constants" do
      expect(described_class.const_defined?(:SOLID_QUEUE_AVAILABLE, false)).to be false
      expect(described_class.const_defined?(:SOLID_CACHE_AVAILABLE, false)).to be false
      expect(described_class.const_defined?(:SOLID_CABLE_AVAILABLE, false)).to be false
    end
  end

  describe "engine-scoped middleware stack" do
    let(:middleware_stack) do
      middleware = described_class.middleware

      return middleware if middleware.is_a?(ActionDispatch::MiddlewareStack)

      stack = ActionDispatch::MiddlewareStack.new
      middleware.merge_into(stack)
      stack
    end
    let(:middleware_classes) { middleware_stack.map(&:klass) }

    it "includes ActionDispatch::Cookies" do
      expect(middleware_classes).to include(ActionDispatch::Cookies)
    end

    it "includes ActionDispatch::Session::CookieStore with the engine-scoped key" do
      session_middleware = middleware_stack.find { |entry| entry.klass == ActionDispatch::Session::CookieStore }

      expect(session_middleware).not_to be_nil
      expect(session_middleware.args).to include(key: "_solid_observer_session")
    end

    it "includes ActionDispatch::Flash" do
      expect(middleware_classes).to include(ActionDispatch::Flash)
    end

    it "orders Cookies before Session before Flash" do
      cookies_index = middleware_classes.index(ActionDispatch::Cookies)
      session_index = middleware_classes.index(ActionDispatch::Session::CookieStore)
      flash_index = middleware_classes.index(ActionDispatch::Flash)

      expect(cookies_index).to be < session_index
      expect(session_index).to be < flash_index
    end
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

  describe ".check_solid_cache_availability" do
    it "warns when SolidCache is not defined and cache observation is enabled" do
      hide_const("SolidCache")
      SolidObserver.config.observe_cache = true

      expect(logger).to receive(:warn).with(/SolidCache not detected/)

      described_class.check_solid_cache_availability
    end

    it "does not warn when SolidCache is not defined and cache observation is disabled" do
      hide_const("SolidCache")
      SolidObserver.config.observe_cache = false

      expect(logger).not_to receive(:warn).with(/SolidCache not detected/)

      described_class.check_solid_cache_availability
    end

    it "does not warn when SolidCache is defined" do
      stub_const("SolidCache", Module.new)
      SolidObserver.config.observe_cache = true

      expect(logger).not_to receive(:warn).with(/SolidCache not detected/)

      described_class.check_solid_cache_availability
    end
  end

  describe ".check_solid_cable_availability" do
    after { SolidObserver.reset_configuration! }

    it "warns when SolidCable is not defined and cable observation is enabled" do
      hide_const("SolidCable")
      SolidObserver.config.observe_cable = true

      expect(logger).to receive(:warn).with(/SolidCable not detected/)

      described_class.check_solid_cable_availability
    end

    it "does not warn when SolidCable is not defined and cable observation is disabled" do
      hide_const("SolidCable")
      SolidObserver.config.observe_cable = false

      expect(logger).not_to receive(:warn).with(/SolidCable not detected/)

      described_class.check_solid_cable_availability
    end

    it "does not warn when SolidCable is defined" do
      stub_const("SolidCable", Module.new)
      SolidObserver.config.observe_cable = true

      expect(logger).not_to receive(:warn).with(/SolidCable not detected/)

      described_class.check_solid_cable_availability
    end
  end

  describe ".check_ui_authentication" do
    after { SolidObserver.reset_configuration! }

    it "is a public class method" do
      expect(described_class.public_methods).to include(:check_ui_authentication)
    end

    context "when UI is disabled" do
      before { SolidObserver.config.ui_enabled = false }

      it "does not log a warning" do
        expect(logger).not_to receive(:warn).with(/authentication/)
        described_class.check_ui_authentication
      end
    end

    context "when UI is enabled and both credentials are set" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = "secret"
      end

      it "does not log a warning" do
        expect(logger).not_to receive(:warn).with(/authentication/)
        described_class.check_ui_authentication
      end
    end

    context "when UI is enabled but neither credential is set" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = nil
        SolidObserver.config.ui_password = nil
      end

      it "logs the no-authentication warning" do
        expect(logger).to receive(:warn).with(
          /WARNING: UI is enabled with no authentication configured/
        )
        described_class.check_ui_authentication
      end
    end

    context "when UI is enabled and only ui_username is set" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = nil
      end

      it "logs a misconfiguration warning naming the missing password" do
        expect(logger).to receive(:warn).with(
          /UI authentication is misconfigured — ui_username is set but ui_password is missing\/nil/
        )
        described_class.check_ui_authentication
      end
    end

    context "when UI is enabled and only ui_password is set" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = nil
        SolidObserver.config.ui_password = "secret"
      end

      it "logs a misconfiguration warning naming the missing username" do
        expect(logger).to receive(:warn).with(
          /UI authentication is misconfigured — ui_password is set but ui_username is missing\/nil/
        )
        described_class.check_ui_authentication
      end
    end
  end

  describe ".configure_database_connection" do
    after { SolidObserver.reset_configuration! }

    it "does not raise or connect models when ActiveRecord is absent" do
      hide_const("ActiveRecord")

      expect(SolidObserver::BaseRecord).not_to receive(:connects_to)

      expect { described_class.configure_database_connection }.not_to raise_error
    end

    it "does not connect observer models when the observer queue database is not configured" do
      configurations = instance_double(ActiveRecord::DatabaseConfigurations)
      allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
      allow(configurations).to receive(:configs_for)
        .with(env_name: Rails.env, name: "solid_observer_queue")
        .and_return(nil)

      expect(SolidObserver::BaseRecord).not_to receive(:connects_to)

      described_class.configure_database_connection
    end

    it "connects observer models when the observer queue database is configured" do
      configurations = instance_double(ActiveRecord::DatabaseConfigurations)
      connection_config = {
        database: {writing: :solid_observer_queue, reading: :solid_observer_queue}
      }

      allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
      allow(configurations).to receive(:configs_for)
        .with(env_name: Rails.env, name: "solid_observer_queue")
        .and_return(Object.new)

      expect(SolidObserver::BaseRecord).to receive(:connects_to).with(**connection_config)

      described_class.configure_database_connection
    end
  end

  describe ".activate_subscribers" do
    let(:pool) { instance_double(ActiveRecord::ConnectionAdapters::ConnectionPool) }
    let(:cache) { instance_double(ActiveRecord::ConnectionAdapters::SchemaCache) }
    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

    before do
      allow(SolidObserver::BaseRecord).to receive(:connection_pool).and_return(pool)
      allow(pool).to receive(:schema_cache).and_return(cache)
      allow(pool).to receive(:with_connection).and_yield(connection)
      allow(cache).to receive(:data_source_exists?).and_return(false)
      allow(connection).to receive(:data_source_exists?).and_return(true)
      allow(SolidObserver::Subscriber).to receive(:subscribe!)
      allow(SolidObserver::CacheSubscriber).to receive(:subscribe!)
      allow(SolidObserver::CableSubscriber).to receive(:subscribe!)
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

    it "handles Trilogy::Error by skipping activation" do
      stub_const("Trilogy::Error", Class.new(StandardError))
      allow(pool).to receive(:with_connection).and_raise(Trilogy::Error)

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

    it "keeps cache activation independent when the enabled queue table is missing" do
      stub_const("SolidCache", Module.new)
      SolidObserver.config.observe_cache = true
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_queue_events").and_return(false)
      allow(connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(false)
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_cache_events").and_return(true)

      expect(logger).to receive(:info).with(/missing: solid_observer_queue_events/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)
      expect(SolidObserver::CacheSubscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "keeps cable activation independent when the enabled queue/cache tables are missing" do
      stub_const("SolidCable", Module.new)
      SolidObserver.config.observe_cable = true
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_queue_events").and_return(false)
      allow(connection).to receive(:data_source_exists?).with("solid_observer_queue_events").and_return(false)
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_cache_events").and_return(false)
      allow(connection).to receive(:data_source_exists?).with("solid_observer_cache_events").and_return(false)
      allow(cache).to receive(:data_source_exists?).with(pool, "solid_observer_cable_events").and_return(true)

      expect(logger).to receive(:info).with(/missing: solid_observer_queue_events/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)
      expect(SolidObserver::CacheSubscriber).not_to receive(:subscribe!)
      expect(SolidObserver::CableSubscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "activates cable subscriber in realtime mode when cable is enabled" do
      stub_const("SolidCable", Module.new)
      SolidObserver.config.observe_cable = true
      SolidObserver.config.storage_mode = :realtime

      expect(SolidObserver::CableSubscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "uses BaseRecord connection pool and never uses ActiveRecord::Base connection APIs" do
      expect(SolidObserver::BaseRecord).to receive(:connection_pool).and_return(pool)
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
