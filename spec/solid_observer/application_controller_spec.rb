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

    it "exposes :solid_queue_available? as a helper method" do
      expect(described_class._helper_methods).to include(:solid_queue_available?)
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

  describe "#solid_queue_available?" do
    it "delegates to QueueStats" do
      expect(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true)
      expect(controller.send(:solid_queue_available?)).to be true
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
