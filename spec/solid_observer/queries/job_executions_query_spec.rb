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

  it "returns a merged array for all_active sorted by created_at desc and preloads jobs" do
    ready_scope = double("ready_scope")
    ready_ordered = double("ready_ordered")
    ready_limited = double("ready_limited")
    scheduled_scope = double("scheduled_scope")
    scheduled_ordered = double("scheduled_ordered")
    scheduled_limited = double("scheduled_limited")
    claimed_scope = double("claimed_scope")
    claimed_ordered = double("claimed_ordered")
    claimed_limited = double("claimed_limited")
    failed_scope = double("failed_scope")
    failed_ordered = double("failed_ordered")
    failed_limited = double("failed_limited")

    ready_record = double("ready_record", created_at: 4.minutes.ago)
    scheduled_record = double("scheduled_record", created_at: 2.minutes.ago)
    claimed_record = double("claimed_record", created_at: 1.minute.ago)
    failed_record = double("failed_record", created_at: 3.minutes.ago)

    allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
    allow(ready_scope).to receive(:order).with(created_at: :desc).and_return(ready_ordered)
    allow(ready_ordered).to receive(:limit).with(50).and_return(ready_limited)
    allow(ready_limited).to receive(:to_a).and_return([ready_record])

    allow(SolidQueue::ScheduledExecution).to receive(:all).and_return(scheduled_scope)
    allow(scheduled_scope).to receive(:order).with(created_at: :desc).and_return(scheduled_ordered)
    allow(scheduled_ordered).to receive(:limit).with(50).and_return(scheduled_limited)
    allow(scheduled_limited).to receive(:to_a).and_return([scheduled_record])

    allow(SolidQueue::ClaimedExecution).to receive(:all).and_return(claimed_scope)
    allow(claimed_scope).to receive(:order).with(created_at: :desc).and_return(claimed_ordered)
    allow(claimed_ordered).to receive(:limit).with(50).and_return(claimed_limited)
    allow(claimed_limited).to receive(:to_a).and_return([claimed_record])

    allow(SolidQueue::FailedExecution).to receive(:all).and_return(failed_scope)
    allow(failed_scope).to receive(:order).with(created_at: :desc).and_return(failed_ordered)
    allow(failed_ordered).to receive(:limit).with(50).and_return(failed_limited)
    allow(failed_limited).to receive(:to_a).and_return([failed_record])

    expected = [claimed_record, scheduled_record, failed_record, ready_record]
    preloader = instance_double(ActiveRecord::Associations::Preloader, call: true)
    expect(ActiveRecord::Associations::Preloader).to receive(:new)
      .with(records: expected, associations: :job)
      .and_return(preloader)

    result = described_class.new(build_filter(status: "all_active")).call

    expect(result).to be_a(Array)
    expect(result).to eq(expected)
  end
end
