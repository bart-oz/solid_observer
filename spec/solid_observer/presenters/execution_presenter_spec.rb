# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::ExecutionPresenter do
  before do
    stub_const("SolidQueue::ReadyExecution", Class.new)
    stub_const("SolidQueue::ScheduledExecution", Class.new)
    stub_const("SolidQueue::ClaimedExecution", Class.new)
    stub_const("SolidQueue::FailedExecution", Class.new)
  end

  describe "#status" do
    it "returns ready for ReadyExecution" do
      presenter = described_class.new(SolidQueue::ReadyExecution.new)
      expect(presenter.status).to eq("ready")
    end

    it "returns scheduled for ScheduledExecution" do
      presenter = described_class.new(SolidQueue::ScheduledExecution.new)
      expect(presenter.status).to eq("scheduled")
    end

    it "returns claimed for ClaimedExecution" do
      presenter = described_class.new(SolidQueue::ClaimedExecution.new)
      expect(presenter.status).to eq("claimed")
    end

    it "returns failed for FailedExecution" do
      presenter = described_class.new(SolidQueue::FailedExecution.new)
      expect(presenter.status).to eq("failed")
    end

    it "returns unknown for unrecognized class" do
      presenter = described_class.new(Object.new)
      expect(presenter.status).to eq("unknown")
    end
  end

  describe "#job" do
    it "delegates to execution.job" do
      job = double("job")
      execution = double("execution", job: job)
      presenter = described_class.new(execution)

      expect(presenter.job).to eq(job)
    end
  end

  describe "#to_model" do
    it "returns the wrapped execution" do
      execution = double("execution")
      presenter = described_class.new(execution)

      expect(presenter.to_model).to eq(execution)
    end
  end
end
