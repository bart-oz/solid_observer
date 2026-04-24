# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::RequirePersistenceMode do
  after { SolidObserver.reset_configuration! }

  let(:controller_class) do
    Class.new(ActionController::Base) do
      include SolidObserver::RequirePersistenceMode

      def root_path
        "/solid_observer"
      end
    end
  end
  let(:controller) { controller_class.allocate }

  describe "class structure" do
    it "registers :require_persistence_mode as a before_action" do
      callbacks = controller_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_persistence_mode)
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
        expect(controller).to receive(:redirect_to).with(
          "/solid_observer",
          alert: "This page is not available in real-time mode."
        )
        controller.send(:require_persistence_mode)
      end
    end
  end
end
