# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::RequireSolidQueue do
  let(:controller_class) do
    Class.new(ActionController::Base) do
      include SolidObserver::RequireSolidQueue

      def root_path
        "/solid_observer"
      end
    end
  end
  let(:controller) { controller_class.allocate }

  describe "class structure" do
    it "registers :require_solid_queue as a before_action" do
      callbacks = controller_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_solid_queue)
    end
  end

  describe "#require_solid_queue" do
    context "when SolidQueue is available" do
      before { allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true) }

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:require_solid_queue)
      end
    end

    context "when SolidQueue is not available" do
      before { allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false) }

      it "redirects to root with an alert" do
        expect(controller).to receive(:redirect_to).with(
          "/solid_observer",
          alert: "SolidQueue is not available."
        )
        controller.send(:require_solid_queue)
      end
    end
  end
end
