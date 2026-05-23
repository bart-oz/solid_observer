# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueStats do
  after do
    SolidObserver::ChartBuffer.clear
    SolidObserver.reset_configuration!
  end

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
    it "delegates to a new instance" do
      instance = instance_double(described_class, snapshot: {ready: 0})
      allow(described_class).to receive(:new).and_return(instance)

      expect(described_class.snapshot(range: "15m")).to eq({ready: 0})
      expect(instance).to have_received(:snapshot).with("15m")
    end
  end

  describe ".parse_range" do
    it "returns allowlisted range keys unchanged" do
      described_class::RANGES.keys.each do |range_key|
        expect(described_class.parse_range(range_key)).to eq(range_key)
      end
    end

    it "falls back to the default for unknown values" do
      expect(described_class.parse_range("999d")).to eq("15m")
      expect(described_class.parse_range(nil)).to eq("15m")
    end
  end

  describe ".range_duration" do
    it "returns configured duration for known keys" do
      expect(described_class.range_duration("15m")).to eq(15.minutes)
    end
  end

  describe ".snapshot_for_poll" do
    it "delegates to a new instance with poll fallback range parsing" do
      instance = instance_double(described_class, snapshot_for_poll: {ready: 1})
      allow(described_class).to receive(:new).and_return(instance)

      expect(described_class.snapshot_for_poll(range: "unknown")).to eq({ready: 1})
      expect(instance).to have_received(:snapshot_for_poll).with("15m")
    end
  end

  describe ".chart_data" do
    it "delegates to a new instance" do
      instance = instance_double(described_class, chart_data: {ready: []})
      allow(described_class).to receive(:new).and_return(instance)

      expect(described_class.chart_data(window: 15.minutes)).to eq({ready: []})
      expect(instance).to have_received(:chart_data).with(15.minutes)
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
          range: "15m",
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

      before do
        allow(ready_execution).to receive(:count).and_return(10)
        allow(scheduled_execution).to receive(:count).and_return(5)
        allow(claimed_execution).to receive(:count).and_return(3)
        allow(failed_execution).to receive(:count).and_return(2)
        allow(process_model).to receive(:where).with(kind: "Worker").and_return(double(count: 4))

        group_double = double
        allow(ready_execution).to receive(:group).with(:queue_name).and_return(group_double)
        allow(group_double).to receive(:count).and_return({"default" => 8, "mailers" => 2})
      end

      context "when persistence_mode? is true" do
        before do
          SolidObserver.config.storage_mode = :persistence
          allow(SolidObserver::QueueEvent).to receive(:performed_count_last).with(15.minutes).and_return(34)
          allow(SolidObserver::QueueEvent).to receive(:failed_count_last).with(15.minutes).and_return(2)
          allow(SolidObserver::QueueEvent).to receive(:enqueue_rate_per_minute).with(window: 15.minutes).and_return(9.1)
          allow(SolidObserver::QueueEvent).to receive(:failed_count_last).with(1.hour).and_return(0)
          allow(SolidObserver::QueueEvent).to receive(:failed_count_last).with(24.hours).and_return(7)
          allow(SolidObserver::QueueEvent).to receive(:recent_failures).with(1).and_return([])
        end

        it "returns snapshot with throughput statistics for the default range" do
          result = queue_stats.snapshot

          expect(result).to eq(
            ready: 10,
            scheduled: 5,
            claimed: 3,
            failed: 2,
            workers: 4,
            queues: {"default" => 8, "mailers" => 2},
            available: true,
            performed_in_range: 34,
            failed_in_range: 2,
            failed_last_24h: 7,
            failed_last_hour: 0,
            latest_failure_at: nil,
            enqueue_rate_per_min: 9.1,
            range: "15m"
          )
        end

        it "uses a requested range window for scoped throughput values" do
          result = queue_stats.snapshot("15m")

          expect(result).to include(
            performed_in_range: 34,
            failed_in_range: 2,
            enqueue_rate_per_min: 9.1,
            range: "15m"
          )
          expect(SolidObserver::QueueEvent).to have_received(:performed_count_last).with(15.minutes)
          expect(SolidObserver::QueueEvent).to have_received(:failed_count_last).with(15.minutes)
          expect(SolidObserver::QueueEvent).to have_received(:enqueue_rate_per_minute).with(window: 15.minutes)
        end
      end

      context "when persistence_mode? is false (realtime)" do
        before do
          SolidObserver.config.storage_mode = :realtime
        end

        it "does not include throughput statistics" do
          expect(SolidObserver::QueueEvent).not_to receive(:performed_count_last)
          expect(SolidObserver::QueueEvent).not_to receive(:failed_count_last)
          expect(SolidObserver::QueueEvent).not_to receive(:enqueue_rate_per_minute)
          expect(SolidObserver::QueueEvent).not_to receive(:recent_failures)

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
      end

      it "returns 0 workers when Process model is not defined" do
        hide_const("SolidQueue::Process")
        SolidObserver.config.storage_mode = :realtime

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
        SolidObserver.config.storage_mode = :realtime

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
          range: "15m",
          error: "Database connection failed"
        )
      end
    end
  end

  describe "#snapshot_for_poll" do
    let(:queue_stats) { described_class.new }
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

      allow(ready_execution).to receive(:count).and_return(6)
      allow(scheduled_execution).to receive(:count).and_return(2)
      allow(claimed_execution).to receive(:count).and_return(1)
      allow(failed_execution).to receive(:count).and_return(3)
      allow(process_model).to receive(:where).with(kind: "Worker").and_return(double(count: 4))
    end

    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      it "returns six-key snapshot including enqueue rate" do
        allow(SolidObserver::QueueEvent).to receive(:enqueue_rate_per_minute).with(window: 15.minutes).and_return(1.6)

        result = queue_stats.snapshot_for_poll("15m")

        expect(result).to eq(
          ready: 6,
          scheduled: 2,
          claimed: 1,
          workers: 4,
          failed: 3,
          enqueue_rate_per_min: 1.6
        )
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "returns nil enqueue rate and skips QueueEvent query" do
        expect(SolidObserver::QueueEvent).not_to receive(:enqueue_rate_per_minute)

        result = queue_stats.snapshot_for_poll("15m")

        expect(result).to eq(
          ready: 6,
          scheduled: 2,
          claimed: 1,
          workers: 4,
          failed: 3,
          enqueue_rate_per_min: nil
        )
      end
    end
  end

  describe "#chart_data" do
    let(:queue_stats) { described_class.new }
    let(:ready_series) { [{t: 1, v: 5}] }

    before do
      allow(SolidObserver::ChartBuffer).to receive(:recent).with(15.minutes.to_i).and_return(ready_series)
    end

    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      it "returns performed, failed and ready series" do
        allow(SolidObserver::QueueEvent).to receive(:count_by_time_bucket).with(
          event_type: "job_completed",
          window: 15.minutes,
          bucket_seconds: 30
        ).and_return([{t: 10, v: 2}])
        allow(SolidObserver::QueueEvent).to receive(:count_by_time_bucket).with(
          event_type: "job_failed",
          window: 15.minutes,
          bucket_seconds: 30
        ).and_return([{t: 10, v: 1}])

        result = queue_stats.chart_data(15.minutes)

        expect(result).to eq(
          performed: [{t: 10, v: 2}],
          failed: [{t: 10, v: 1}],
          ready: ready_series
        )
      end

      it "uses bucket sizes by window band" do
        windows_and_buckets = {
          30.minutes => 30,
          2.hours => 60,
          1.day => 5.minutes.to_i,
          2.days => 30.minutes.to_i
        }

        windows_and_buckets.each do |window, expected_bucket|
          allow(SolidObserver::ChartBuffer).to receive(:recent).with(window.to_i).and_return([])
          allow(SolidObserver::QueueEvent).to receive(:count_by_time_bucket).with(
            event_type: "job_completed",
            window: window,
            bucket_seconds: expected_bucket
          ).and_return([])
          allow(SolidObserver::QueueEvent).to receive(:count_by_time_bucket).with(
            event_type: "job_failed",
            window: window,
            bucket_seconds: expected_bucket
          ).and_return([])

          queue_stats.chart_data(window)
        end
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "returns empty throughput series and keeps ready samples" do
        expect(SolidObserver::QueueEvent).not_to receive(:count_by_time_bucket)

        result = queue_stats.chart_data(15.minutes)

        expect(result).to eq(
          performed: [],
          failed: [],
          ready: ready_series
        )
      end
    end
  end
end
