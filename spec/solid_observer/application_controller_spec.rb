# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::ApplicationController, type: :controller do
  after { SolidObserver.reset_configuration! }

  let(:controller_test_class) do
    Class.new(described_class) do
      public :verify_ui_enabled,
        :authenticate,
        :credentials_valid?,
        :persistence_mode?,
        :realtime_mode?,
        :solid_queue_available?
    end
  end
  let(:controller_instance) { controller_test_class.allocate }

  describe "class structure" do
    it "inherits from ActionController::Base" do
      expect(described_class.superclass).to eq(ActionController::Base)
    end

    it "registers :verify_ui_enabled as a before_action" do
      callbacks = described_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:verify_ui_enabled)
    end

    it "registers :authenticate as a before_action" do
      callbacks = described_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:authenticate)
    end

    it "exposes :persistence_mode? as a helper method" do
      expect(described_class._helper_methods).to include(:persistence_mode?)
    end

    it "exposes :realtime_mode? as a helper method" do
      expect(described_class._helper_methods).to include(:realtime_mode?)
    end

    it "exposes :solid_queue_available? as a helper method" do
      expect(described_class._helper_methods).to include(:solid_queue_available?)
    end

    it "uses the solid_observer/application layout" do
      expect(described_class._layout).to eq("solid_observer/application")
    end
  end

  describe "#verify_ui_enabled" do
    context "when ui_enabled is true" do
      before { SolidObserver.config.ui_enabled = true }

      it "does not render a 404" do
        expect(controller_instance).not_to receive(:render)
        controller_instance.verify_ui_enabled
      end
    end

    context "when ui_enabled is false" do
      before { SolidObserver.config.ui_enabled = false }

      it "renders a plain 404 Not Found response" do
        expect(controller_instance).to receive(:render).with(plain: "Not Found", status: :not_found)
        controller_instance.verify_ui_enabled
      end
    end
  end

  describe "#authenticate" do
    context "when no ui_username is configured" do
      before { SolidObserver.config.ui_username = nil }

      it "skips HTTP Basic Auth entirely" do
        expect(controller_instance).not_to receive(:authenticate_or_request_with_http_basic)
        controller_instance.authenticate
      end
    end

    context "when ui_username is set but ui_password is missing" do
      before do
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = nil
      end

      it "skips HTTP Basic Auth (does not enable auth with a blank password)" do
        expect(controller_instance).not_to receive(:authenticate_or_request_with_http_basic)
        controller_instance.authenticate
      end
    end

    context "when ui_password is set but ui_username is missing" do
      before do
        SolidObserver.config.ui_username = nil
        SolidObserver.config.ui_password = "secret"
      end

      it "skips HTTP Basic Auth (both credentials must be configured)" do
        expect(controller_instance).not_to receive(:authenticate_or_request_with_http_basic)
        controller_instance.authenticate
      end
    end

    context "when ui_username is configured" do
      before do
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = "secret"
      end

      it "triggers HTTP Basic Auth" do
        expect(controller_instance).to receive(:authenticate_or_request_with_http_basic).with("SolidObserver")
        controller_instance.authenticate
      end

      it "delegates credential checking to credentials_valid?" do
        allow(controller_instance).to receive(:authenticate_or_request_with_http_basic).and_yield("admin", "secret")
        expect(controller_instance).to receive(:credentials_valid?).with("admin", "secret").and_call_original
        controller_instance.authenticate
      end
    end
  end

  describe "#credentials_valid?" do
    before do
      SolidObserver.config.ui_username = "admin"
      SolidObserver.config.ui_password = "secret"
    end

    it "returns true for correct credentials" do
      expect(controller_instance.credentials_valid?("admin", "secret")).to be true
    end

    it "returns false for wrong password" do
      expect(controller_instance.credentials_valid?("admin", "wrong")).to be false
    end

    it "returns false for wrong username" do
      expect(controller_instance.credentials_valid?("hacker", "secret")).to be false
    end

    it "uses secure_compare for both username and password" do
      expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).twice.and_call_original
      controller_instance.credentials_valid?("admin", "secret")
    end
  end

  describe "#persistence_mode?" do
    it "returns true in persistence mode" do
      SolidObserver.config.storage_mode = :persistence
      expect(controller_instance.persistence_mode?).to be true
    end

    it "returns false in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      expect(controller_instance.persistence_mode?).to be false
    end
  end

  describe "#realtime_mode?" do
    it "returns false in persistence mode" do
      SolidObserver.config.storage_mode = :persistence
      expect(controller_instance.realtime_mode?).to be false
    end

    it "returns true in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      expect(controller_instance.realtime_mode?).to be true
    end
  end

  describe "#solid_queue_available?" do
    it "delegates to QueueStats" do
      expect(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true)
      expect(controller_instance.solid_queue_available?).to be true
    end
  end

  describe "API-only app compatibility" do
    it "detects an API-only base controller correctly" do
      stub_const("FakeApiController", Class.new(ActionController::API))
      expect(FakeApiController.ancestors).to include(ActionController::API)
    end

    it "does not detect a standard base controller as API-only" do
      stub_const("FakeStandardController", Class.new(ActionController::Base))
      expect(FakeStandardController.ancestors).not_to include(ActionController::API)
    end
  end

  describe "adapter-specific rescue registration" do
    def temp_controller_class
      Class.new(SolidObserver::ApplicationController) do
        rescue_from ActiveRecord::NoDatabaseError,
          ActiveRecord::ConnectionNotEstablished,
          *SolidObserver::ApplicationController.runtime_db_errors,
          with: :render_storage_unavailable
      end
    end

    def rescue_classes(klass)
      klass.rescue_handlers.map(&:first)
    end

    it "registers PG::ConnectionBad when defined at class load" do
      stub_const("PG::ConnectionBad", Class.new(StandardError))
      expect(rescue_classes(temp_controller_class)).to include("PG::ConnectionBad")
    end

    it "registers Mysql2::Error::ConnectionError when defined at class load" do
      stub_const("Mysql2::Error::ConnectionError", Class.new(StandardError))
      expect(rescue_classes(temp_controller_class)).to include("Mysql2::Error::ConnectionError")
    end

    it "registers SQLite3::CantOpenException when defined at class load" do
      stub_const("SQLite3::CantOpenException", Class.new(StandardError))
      expect(rescue_classes(temp_controller_class)).to include("SQLite3::CantOpenException")
    end

    it "skips adapter classes that are not defined at class load" do
      hide_const("PG::ConnectionBad")
      hide_const("Mysql2::Error::ConnectionError")
      hide_const("SQLite3::CantOpenException")

      classes = rescue_classes(temp_controller_class)
      expect(classes).not_to include("PG::ConnectionBad")
      expect(classes).not_to include("Mysql2::Error::ConnectionError")
    end
  end

  describe "DB unavailability rescue" do
    let(:request_controller_class) do
      Class.new(SolidObserver::ApplicationController) do
        append_view_path File.expand_path("../../app/views", __dir__)

        helper_method :root_path, :jobs_path, :events_path, :storage_path

        class << self
          attr_accessor :error_to_raise
        end

        def index
          raise self.class.error_to_raise
        end

        def root_path
          "/solid_observer"
        end

        def jobs_path
          "/solid_observer/jobs"
        end

        def events_path
          "/solid_observer/events"
        end

        def storage_path
          "/solid_observer/storage"
        end
      end
    end

    def perform_request(klass)
      body = +""
      rack_body = nil

      status, _headers, rack_body = klass.action(:index).call(Rack::MockRequest.env_for("/index"))
      rack_body.each { |chunk| body << chunk }

      [status, body]
    ensure
      rack_body.close if rack_body.respond_to?(:close)
    end

    before do
      SolidObserver.config.ui_enabled = true
      SolidObserver.config.ui_username = nil
      SolidObserver.config.ui_password = nil
    end

    it "renders storage_unavailable view at 503 for NoDatabaseError" do
      request_controller_class.error_to_raise = ActiveRecord::NoDatabaseError.new("boom: db missing")

      status, body = perform_request(request_controller_class)

      expect(status).to eq(503)
      expect(body).to include("SolidObserver storage is not reachable")
      expect(body).to include("ActiveRecord::NoDatabaseError")
      expect(body).to include("boom: db missing")
    end

    it "renders storage_unavailable view at 503 for ConnectionNotEstablished" do
      request_controller_class.error_to_raise = ActiveRecord::ConnectionNotEstablished.new("pool closed")

      status, body = perform_request(request_controller_class)

      expect(status).to eq(503)
      expect(body).to include("pool closed")
    end

    it "does NOT rescue unrelated StandardError" do
      request_controller_class.error_to_raise = StandardError.new("totally unrelated")

      expect {
        perform_request(request_controller_class)
      }.to raise_error(StandardError, "totally unrelated")
    end
  end

  describe "realtime mode behavior" do
    it "keeps dashboard DB-free on the happy path in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      dashboard = SolidObserver::DashboardController.allocate
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return({})
      expect(SolidObserver::QueueEvent).not_to receive(:recent)
      expect(SolidObserver::QueueEvent).not_to receive(:recent_failures)

      expect { dashboard.public_send(:index) }.not_to raise_error
    end
  end
end
