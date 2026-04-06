# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::DashboardController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end
  end

  describe "#index" do
    let(:stats) { {ready: 3, scheduled: 1, claimed: 0, failed: 2, workers: 1, queues: {}, available: true} }

    before do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
    end

    it "assigns @stats from QueueStats.snapshot" do
      SolidObserver.config.storage_mode = :realtime
      controller.send(:index)
      expect(controller.instance_variable_get(:@stats)).to eq(stats)
    end

    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      let(:events_scope) { double("events_scope") }
      let(:failures_scope) { double("failures_scope") }

      before do
        allow(SolidObserver::QueueEvent).to receive(:recent).with(10).and_return(events_scope)
        allow(SolidObserver::QueueEvent).to receive(:recent_failures).with(5).and_return(failures_scope)
      end

      it "assigns @recent_events" do
        controller.send(:index)
        expect(controller.instance_variable_get(:@recent_events)).to eq(events_scope)
      end

      it "assigns @recent_failures" do
        controller.send(:index)
        expect(controller.instance_variable_get(:@recent_failures)).to eq(failures_scope)
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "does not assign @recent_events" do
        controller.send(:index)
        expect(controller.instance_variable_get(:@recent_events)).to be_nil
      end

      it "does not assign @recent_failures" do
        controller.send(:index)
        expect(controller.instance_variable_get(:@recent_failures)).to be_nil
      end
    end
  end
end
