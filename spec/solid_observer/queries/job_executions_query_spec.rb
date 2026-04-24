# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Queries::JobExecutionsQuery do
  before do
    stub_const("SolidQueue", Module.new)
    stub_const("SolidQueue::ReadyExecution", Class.new {
      def self.all
      end
    })
    stub_const("SolidQueue::ScheduledExecution", Class.new {
      def self.all
      end
    })
    stub_const("SolidQueue::ClaimedExecution", Class.new {
      def self.all
      end
    })
    stub_const("SolidQueue::FailedExecution", Class.new {
      def self.all
      end
    })
    stub_const("SolidQueue::Job", Class.new {
      def self.distinct
      end
    })
  end

  let(:filter_class) { Struct.new(:status, :queue_name, :job_class, keyword_init: true) }

  def build_filter(status: "ready", queue_name: nil, job_class: nil)
    filter_class.new(status: status, queue_name: queue_name, job_class: job_class)
  end

  it "returns ReadyExecution for ready status" do
    ready_scope = double("ready_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
    allow(ready_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "ready")).call
    expect(result).to eq(ordered_scope)
  end

  it "returns ScheduledExecution for scheduled status" do
    scheduled_scope = double("scheduled_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ScheduledExecution).to receive(:all).and_return(scheduled_scope)
    allow(scheduled_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "scheduled")).call
    expect(result).to eq(ordered_scope)
  end

  it "returns ClaimedExecution for claimed status" do
    claimed_scope = double("claimed_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ClaimedExecution).to receive(:all).and_return(claimed_scope)
    allow(claimed_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "claimed")).call
    expect(result).to eq(ordered_scope)
  end

  it "returns FailedExecution for failed status" do
    failed_scope = double("failed_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::FailedExecution).to receive(:all).and_return(failed_scope)
    allow(failed_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "failed")).call
    expect(result).to eq(ordered_scope)
  end

  it "defaults to ReadyExecution for unknown status" do
    ready_scope = double("ready_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
    allow(ready_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "unknown_status")).call
    expect(result).to eq(ordered_scope)
  end

  it "filters by queue_name directly for ready status" do
    ready_scope = double("ready_scope")
    filtered_scope = double("filtered_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
    allow(ready_scope).to receive(:where).with(queue_name: "default").and_return(filtered_scope)
    allow(filtered_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "ready", queue_name: "default")).call
    expect(result).to eq(ordered_scope)
  end

  it "joins through job table for failed status queue filter" do
    failed_scope = double("failed_scope")
    joined_scope = double("joined_scope")
    filtered_scope = double("filtered_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::FailedExecution).to receive(:all).and_return(failed_scope)
    allow(failed_scope).to receive(:joins).with(:job).and_return(joined_scope)
    allow(joined_scope).to receive(:where).with(solid_queue_jobs: {queue_name: "default"}).and_return(filtered_scope)
    allow(filtered_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "failed", queue_name: "default")).call
    expect(result).to eq(ordered_scope)
  end

  it "joins through job table for claimed status queue filter" do
    claimed_scope = double("claimed_scope")
    joined_scope = double("joined_scope")
    filtered_scope = double("filtered_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ClaimedExecution).to receive(:all).and_return(claimed_scope)
    allow(claimed_scope).to receive(:joins).with(:job).and_return(joined_scope)
    allow(joined_scope).to receive(:where).with(solid_queue_jobs: {queue_name: "urgent"}).and_return(filtered_scope)
    allow(filtered_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "claimed", queue_name: "urgent")).call
    expect(result).to eq(ordered_scope)
  end

  it "joins job table and filters by class_name when job_class present" do
    ready_scope = double("ready_scope")
    joined_scope = double("joined_scope")
    filtered_scope = double("filtered_scope")
    ordered_scope = double("ordered_scope")
    allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
    allow(ready_scope).to receive(:joins).with(:job).and_return(joined_scope)
    allow(joined_scope).to receive(:where).with(solid_queue_jobs: {class_name: "MyJob"}).and_return(filtered_scope)
    allow(filtered_scope).to receive(:order).with(created_at: :desc).and_return(ordered_scope)

    result = described_class.new(build_filter(status: "ready", job_class: "MyJob")).call
    expect(result).to eq(ordered_scope)
  end
end
