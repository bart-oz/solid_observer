# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::StoragesController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end

    it "registers :require_persistence_mode as a before_action" do
      callbacks = described_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_persistence_mode)
    end
  end

  describe "#show" do
    let(:components) { [{component: "queue_observer"}] }
    let(:history) { [double("snap1"), double("snap2")] }

    before do
      allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return(components)
      allow(SolidObserver::StorageInfo).to receive(:recent).with(20).and_return(history)
    end

    it "assigns @storage_components" do
      controller.send(:show)
      expect(controller.instance_variable_get(:@storage_components)).to eq(components)
    end

    it "assigns @storage_history with 20 recent records" do
      controller.send(:show)
      expect(controller.instance_variable_get(:@storage_history)).to eq(history)
    end
  end
end
