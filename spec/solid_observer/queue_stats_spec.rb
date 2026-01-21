# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueStats do
  describe ".solid_queue_available?" do
    context "when SolidQueue is defined" do
      it "returns true" do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)

        expect(described_class.solid_queue_available?).to be true
      end
    end

    context "when SolidQueue is not defined" do
      it "returns false" do
        hide_const("SolidQueue")

        expect(described_class.solid_queue_available?).to be false
      end
    end

    context "when SolidQueue is defined but Job class is missing" do
      it "returns false" do
        stub_const("SolidQueue", Module.new)

        expect(described_class.solid_queue_available?).to be false
      end
    end
  end

  describe ".snapshot" do
    it "creates an instance and calls #snapshot" do
      allow_any_instance_of(described_class).to receive(:snapshot).and_return({ready: 0})
      expect(described_class.snapshot).to eq({ready: 0})
    end
  end

  describe "#snapshot" do
    let(:queue_stats) { described_class.new }

    context "when SolidQueue is not available" do
      before do
        allow(described_class).to receive(:solid_queue_available?).and_return(false)
      end

      it "returns unavailable response" do
        result = queue_stats.snapshot

        expect(result).to include(
          ready: 0,
          scheduled: 0,
          claimed: 0,
          failed: 0,
          workers: 0,
          queues: {},
          available: false,
          error: "SolidQueue not available"
        )
      end
    end

    context "when SolidQueue is available" do
      let(:ready_execution) { double("ReadyExecution") }
      let(:scheduled_execution) { double("ScheduledExecution") }
      let(:claimed_execution) { double("ClaimedExecution") }
      let(:failed_execution) { double("FailedExecution") }
      let(:process_model) { double("Process") }

      before do
        stub_const("SolidQueue", Module.new)
        stub_const("SolidQueue::Job", Class.new)
        stub_const("SolidQueue::ReadyExecution", ready_execution)
        stub_const("SolidQueue::ScheduledExecution", scheduled_execution)
        stub_const("SolidQueue::ClaimedExecution", claimed_execution)
        stub_const("SolidQueue::FailedExecution", failed_execution)
        stub_const("SolidQueue::Process", process_model)

        allow(described_class).to receive(:solid_queue_available?).and_return(true)
      end

      it "returns snapshot with all statistics" do
        allow(ready_execution).to receive(:count).and_return(10)
        allow(scheduled_execution).to receive(:count).and_return(5)
        allow(claimed_execution).to receive(:count).and_return(3)
        allow(failed_execution).to receive(:count).and_return(2)
        allow(process_model).to receive(:where).with(kind: "Worker").and_return(double(count: 4))

        group_double = double
        allow(ready_execution).to receive(:group).with(:queue_name).and_return(group_double)
        allow(group_double).to receive(:count).and_return({"default" => 8, "mailers" => 2})

        result = queue_stats.snapshot

        expect(result).to eq(
          ready: 10,
          scheduled: 5,
          claimed: 3,
          failed: 2,
          workers: 4,
          queues: {"default" => 8, "mailers" => 2},
          available: true
        )
      end

      it "returns 0 workers when Process model is not defined" do
        hide_const("SolidQueue::Process")

        allow(ready_execution).to receive(:count).and_return(10)
        allow(scheduled_execution).to receive(:count).and_return(5)
        allow(claimed_execution).to receive(:count).and_return(3)
        allow(failed_execution).to receive(:count).and_return(2)

        group_double = double
        allow(ready_execution).to receive(:group).with(:queue_name).and_return(group_double)
        allow(group_double).to receive(:count).and_return({})

        result = queue_stats.snapshot

        expect(result[:workers]).to eq(0)
      end

      it "returns empty hash for queues when ReadyExecution is not defined" do
        hide_const("SolidQueue::ReadyExecution")
        stub_const("SolidQueue::ReadyExecution", nil)

        allow(queue_stats).to receive(:ready_count).and_return(0)
        allow(scheduled_execution).to receive(:count).and_return(5)
        allow(claimed_execution).to receive(:count).and_return(3)
        allow(failed_execution).to receive(:count).and_return(2)
        allow(process_model).to receive(:where).with(kind: "Worker").and_return(double(count: 4))

        result = queue_stats.snapshot

        expect(result[:queues]).to eq({})
      end
    end

    context "when an error occurs during snapshot" do
      before do
        allow(described_class).to receive(:solid_queue_available?).and_return(true)
        allow(queue_stats).to receive(:ready_count).and_raise(StandardError.new("Database connection failed"))
      end

      it "returns error response with exception message" do
        result = queue_stats.snapshot

        expect(result).to include(
          ready: 0,
          scheduled: 0,
          claimed: 0,
          failed: 0,
          workers: 0,
          queues: {},
          available: false,
          error: "Database connection failed"
        )
      end
    end
  end

  describe "private methods" do
    let(:queue_stats) { described_class.new }

    describe "#ready_count" do
      it "queries ReadyExecution count" do
        ready_execution = double("ReadyExecution", count: 15)
        stub_const("SolidQueue::ReadyExecution", ready_execution)

        expect(queue_stats.send(:ready_count)).to eq(15)
      end
    end

    describe "#scheduled_count" do
      it "queries ScheduledExecution count" do
        scheduled_execution = double("ScheduledExecution", count: 20)
        stub_const("SolidQueue::ScheduledExecution", scheduled_execution)

        expect(queue_stats.send(:scheduled_count)).to eq(20)
      end
    end

    describe "#claimed_count" do
      it "queries ClaimedExecution count" do
        claimed_execution = double("ClaimedExecution", count: 7)
        stub_const("SolidQueue::ClaimedExecution", claimed_execution)

        expect(queue_stats.send(:claimed_count)).to eq(7)
      end
    end

    describe "#failed_count" do
      it "queries FailedExecution count" do
        failed_execution = double("FailedExecution", count: 4)
        stub_const("SolidQueue::FailedExecution", failed_execution)

        expect(queue_stats.send(:failed_count)).to eq(4)
      end
    end

    describe "#active_workers_count" do
      it "queries Process count for Workers" do
        process_model = double("Process")
        stub_const("SolidQueue::Process", process_model)
        allow(process_model).to receive(:where).with(kind: "Worker").and_return(double(count: 6))

        expect(queue_stats.send(:active_workers_count)).to eq(6)
      end

      it "returns 0 when Process model is not defined" do
        hide_const("SolidQueue::Process")

        expect(queue_stats.send(:active_workers_count)).to eq(0)
      end
    end

    describe "#queue_depths" do
      it "groups ReadyExecution by queue_name and counts" do
        ready_execution = double("ReadyExecution")
        stub_const("SolidQueue::ReadyExecution", ready_execution)

        group_double = double
        allow(ready_execution).to receive(:group).with(:queue_name).and_return(group_double)
        allow(group_double).to receive(:count).and_return({"default" => 10, "mailers" => 5, "urgent" => 2})

        expect(queue_stats.send(:queue_depths)).to eq({"default" => 10, "mailers" => 5, "urgent" => 2})
      end

      it "returns empty hash when ReadyExecution is not defined" do
        hide_const("SolidQueue::ReadyExecution")

        expect(queue_stats.send(:queue_depths)).to eq({})
      end
    end
  end
end
