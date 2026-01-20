# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CleanupJob do
  describe "#perform" do
    it "calls CleanupStorage service" do
      expect(SolidObserver::Services::CleanupStorage).to receive(:call)

      described_class.new.perform
    end

    it "queues on default queue" do
      expect(described_class.new.queue_name).to eq("default")
    end
  end
end
