# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Queries::ExecutionFinder do
  before do
    stub_const("SolidQueue", Module.new)
    stub_const("SolidQueue::ReadyExecution", Class.new {
      def self.find_by(id:)
      end
    })
    stub_const("SolidQueue::ScheduledExecution", Class.new {
      def self.find_by(id:)
      end
    })
    stub_const("SolidQueue::ClaimedExecution", Class.new {
      def self.find_by(id:)
      end
    })
    stub_const("SolidQueue::FailedExecution", Class.new {
      def self.find_by(id:)
      end
    })
  end

  describe ".find_any" do
    it "returns ReadyExecution when found" do
      execution = double("execution")
      allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: "1").and_return(execution)

      expect(described_class.find_any("1")).to eq(execution)
    end

    it "checks other types when ReadyExecution not found" do
      allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: "2").and_return(nil)
      execution = double("execution")
      allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: "2").and_return(execution)

      expect(described_class.find_any("2")).to eq(execution)
    end

    it "returns nil when not found in any execution type" do
      allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: "999").and_return(nil)
      allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: "999").and_return(nil)
      allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: "999").and_return(nil)
      allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "999").and_return(nil)

      expect(described_class.find_any("999")).to be_nil
    end
  end

  describe ".find_failed" do
    it "returns failed execution when found" do
      execution = double("execution")
      allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "5").and_return(execution)

      expect(described_class.find_failed("5")).to eq(execution)
    end

    it "returns nil when FailedExecution constant is unavailable" do
      hide_const("SolidQueue::FailedExecution")
      expect(described_class.find_failed("5")).to be_nil
    end
  end
end
