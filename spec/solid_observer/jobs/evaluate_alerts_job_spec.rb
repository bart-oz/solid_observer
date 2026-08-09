# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::EvaluateAlertsJob do
  describe "#perform" do
    it "calls Services::EvaluateAlerts service" do
      expect(SolidObserver::Services::EvaluateAlerts).to receive(:call)

      described_class.new.perform
    end

    it "queues on default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
