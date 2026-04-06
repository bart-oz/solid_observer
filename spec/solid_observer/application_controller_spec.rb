# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::ApplicationController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }
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

    it "uses the solid_observer/application layout" do
      expect(controller.send(:_layout, nil, nil, nil)).to eq("solid_observer/application")
    end
  end
  describe "#verify_ui_enabled" do
    context "when ui_enabled is true" do
      before { SolidObserver.config.ui_enabled = true }

      it "does not render a 404" do
        expect(controller).not_to receive(:render)
        controller.send(:verify_ui_enabled)
      end
    end

    context "when ui_enabled is false" do
      before { SolidObserver.config.ui_enabled = false }

      it "renders a plain 404 Not Found response" do
        expect(controller).to receive(:render).with(plain: "Not Found", status: :not_found)
        controller.send(:verify_ui_enabled)
      end
    end
  end
  describe "#authenticate" do
    context "when no ui_username is configured" do
      before { SolidObserver.config.ui_username = nil }

      it "skips HTTP Basic Auth entirely" do
        expect(controller).not_to receive(:authenticate_or_request_with_http_basic)
        controller.send(:authenticate)
      end
    end

    context "when ui_username is configured" do
      before do
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = "secret"
      end

      it "triggers HTTP Basic Auth" do
        expect(controller).to receive(:authenticate_or_request_with_http_basic).with("SolidObserver")
        controller.send(:authenticate)
      end

      it "delegates credential checking to credentials_valid?" do
        allow(controller).to receive(:authenticate_or_request_with_http_basic).and_yield("admin", "secret")
        expect(controller).to receive(:credentials_valid?).with("admin", "secret").and_call_original
        controller.send(:authenticate)
      end
    end
  end

  describe "#credentials_valid?" do
    before do
      SolidObserver.config.ui_username = "admin"
      SolidObserver.config.ui_password = "secret"
    end

    it "returns true for correct credentials" do
      expect(controller.send(:credentials_valid?, "admin", "secret")).to be true
    end

    it "returns false for wrong password" do
      expect(controller.send(:credentials_valid?, "admin", "wrong")).to be false
    end

    it "returns false for wrong username" do
      expect(controller.send(:credentials_valid?, "hacker", "secret")).to be false
    end

    it "uses secure_compare for both username and password" do
      expect(ActiveSupport::SecurityUtils).to receive(:secure_compare).twice.and_call_original
      controller.send(:credentials_valid?, "admin", "secret")
    end
  end

  describe "#persistence_mode?" do
    it "returns true in persistence mode" do
      SolidObserver.config.storage_mode = :persistence
      expect(controller.send(:persistence_mode?)).to be true
    end

    it "returns false in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      expect(controller.send(:persistence_mode?)).to be false
    end
  end

  describe "#realtime_mode?" do
    it "returns false in persistence mode" do
      SolidObserver.config.storage_mode = :persistence
      expect(controller.send(:realtime_mode?)).to be false
    end

    it "returns true in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      expect(controller.send(:realtime_mode?)).to be true
    end
  end
  describe "#require_persistence_mode" do
    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:require_persistence_mode)
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "redirects to root with an alert" do
        controller.define_singleton_method(:root_path) { "/solid_observer" }
        expect(controller).to receive(:redirect_to).with(
          "/solid_observer",
          alert: "This page is not available in real-time mode."
        )
        controller.send(:require_persistence_mode)
      end
    end
  end
  describe "#require_solid_queue" do
    context "when SolidQueue is available" do
      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)
      end

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:require_solid_queue)
      end
    end

    context "when SolidQueue is not available" do
      it "redirects to root with an alert" do
        controller.define_singleton_method(:root_path) { "/solid_observer" }
        expect(controller).to receive(:redirect_to).with(
          "/solid_observer",
          alert: "SolidQueue is not available."
        )
        controller.send(:require_solid_queue)
      end
    end
  end

  describe "#solid_queue_available?" do
    context "when SolidQueue and SolidQueue::Job are defined" do
      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)
      end

      it "returns true" do
        expect(controller.send(:solid_queue_available?)).to be true
      end
    end

    context "when SolidQueue is not defined" do
      it "returns false" do
        hide_const("SolidQueue") if defined?(SolidQueue)
        expect(controller.send(:solid_queue_available?)).to be false
      end
    end
  end

  describe "#determine_status" do
    before do
      stub_const("SolidQueue::ReadyExecution", Class.new)
      stub_const("SolidQueue::ScheduledExecution", Class.new)
      stub_const("SolidQueue::ClaimedExecution", Class.new)
      stub_const("SolidQueue::FailedExecution", Class.new)
    end

    it "returns 'ready' for ReadyExecution" do
      execution = SolidQueue::ReadyExecution.new
      expect(controller.send(:determine_status, execution)).to eq("ready")
    end

    it "returns 'scheduled' for ScheduledExecution" do
      execution = SolidQueue::ScheduledExecution.new
      expect(controller.send(:determine_status, execution)).to eq("scheduled")
    end

    it "returns 'claimed' for ClaimedExecution" do
      execution = SolidQueue::ClaimedExecution.new
      expect(controller.send(:determine_status, execution)).to eq("claimed")
    end

    it "returns 'failed' for FailedExecution" do
      execution = SolidQueue::FailedExecution.new
      expect(controller.send(:determine_status, execution)).to eq("failed")
    end

    it "returns 'unknown' for unrecognized class" do
      expect(controller.send(:determine_status, Object.new)).to eq("unknown")
    end
  end

  describe "#normalize_page" do
    it "sets @page to 1 when below 1" do
      controller.instance_variable_set(:@page, 0)
      controller.instance_variable_set(:@total_pages, 5)
      controller.send(:normalize_page)
      expect(controller.instance_variable_get(:@page)).to eq(1)
    end

    it "sets @page to 1 when above total_pages" do
      controller.instance_variable_set(:@page, 10)
      controller.instance_variable_set(:@total_pages, 3)
      controller.send(:normalize_page)
      expect(controller.instance_variable_get(:@page)).to eq(1)
    end

    it "does not change @page when within valid range" do
      controller.instance_variable_set(:@page, 2)
      controller.instance_variable_set(:@total_pages, 5)
      controller.send(:normalize_page)
      expect(controller.instance_variable_get(:@page)).to eq(2)
    end

    it "does not clamp when total_pages is 0" do
      controller.instance_variable_set(:@page, 1)
      controller.instance_variable_set(:@total_pages, 0)
      controller.send(:normalize_page)
      expect(controller.instance_variable_get(:@page)).to eq(1)
    end
  end

  describe "#paginate_scope" do
    let(:scope) { double("scope", count: 60) }

    before { controller.instance_variable_set(:@page, 2) }

    it "sets @total_count from scope.count" do
      controller.send(:paginate_scope, scope, per_page: 25)
      expect(controller.instance_variable_get(:@total_count)).to eq(60)
    end

    it "sets @total_pages based on count and per_page" do
      controller.send(:paginate_scope, scope, per_page: 25)
      expect(controller.instance_variable_get(:@total_pages)).to eq(3)
    end

    it "returns the correct offset for page 2" do
      offset = controller.send(:paginate_scope, scope, per_page: 25)
      expect(offset).to eq(25)
    end

    it "returns offset 0 for page 1" do
      controller.instance_variable_set(:@page, 1)
      offset = controller.send(:paginate_scope, scope, per_page: 25)
      expect(offset).to eq(0)
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
end
