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

  describe "#queue_name" do
    it "returns execution queue_name when execution exposes it" do
      job = double("job", queue_name: "mailers")
      execution = double("execution", job: job, queue_name: "critical")

      expect(described_class.new(execution).queue_name).to eq("critical")
    end

    it "returns job queue_name when execution does not expose it" do
      job = double("job", queue_name: "fallback")
      execution = double("failed_execution", job: job)

      expect(described_class.new(execution).queue_name).to eq("fallback")
    end

    it "returns nil when neither execution nor job exposes queue_name" do
      execution = double("failed_execution", job: nil)

      expect(described_class.new(execution).queue_name).to be_nil
    end

    it "returns nil when job is non-nil but does not expose queue_name" do
      job_without_attr = double("job_without_queue_name")
      execution = double("failed_execution", job: job_without_attr)

      expect(described_class.new(execution).queue_name).to be_nil
    end
  end

  describe "#priority" do
    it "returns execution priority when execution exposes it" do
      job = double("job", priority: 5)
      execution = double("execution", job: job, priority: 2)

      expect(described_class.new(execution).priority).to eq(2)
    end

    it "returns job priority when execution does not expose it" do
      job = double("job", priority: 7)
      execution = double("failed_execution", job: job)

      expect(described_class.new(execution).priority).to eq(7)
    end

    it "returns nil when neither execution nor job exposes priority" do
      execution = double("failed_execution", job: nil)

      expect(described_class.new(execution).priority).to be_nil
    end

    it "returns nil when job is non-nil but does not expose priority" do
      job_without_attr = double("job_without_priority")
      execution = double("failed_execution", job: job_without_attr)

      expect(described_class.new(execution).priority).to be_nil
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
