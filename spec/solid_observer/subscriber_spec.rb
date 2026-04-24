# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Subscriber do
  before do
    # Engine boot (via dummy app) subscribes globally. Clear before each example
    # so tests operate on a fresh notifier state and assertions aren't affected
    # by pre-existing ActiveSupport::Notifications listeners.
    described_class.unsubscribe!
    allow(SolidObserver::Services::RecordEvent).to receive(:call)
  end

  after do
    described_class.unsubscribe!
  end

  describe ".subscribe!" do
    context "when observe_queue is disabled" do
      it "does not subscribe to events" do
        allow(SolidObserver.config).to receive(:observe_queue).and_return(false)

        before_count = ActiveSupport::Notifications.notifier.listeners_for("enqueue.active_job").size

        described_class.subscribe!

        after_count = ActiveSupport::Notifications.notifier.listeners_for("enqueue.active_job").size
        expect(after_count).to eq(before_count)
      end
    end

    context "when observe_queue is enabled" do
      before do
        allow(SolidObserver.config).to receive(:observe_queue).and_return(true)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      end

      it "subscribes to enqueue.active_job" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: mock_job})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_enqueued", metric_name: "jobs_enqueued")
        )
      end

      it "subscribes to perform.active_job" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        ActiveSupport::Notifications.instrument("perform.active_job", {job: mock_job})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_completed", metric_name: "jobs_completed")
        )
      end

      it "subscribes to retry_stopped.active_job" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        mock_error = StandardError.new("test error")
        ActiveSupport::Notifications.instrument("retry_stopped.active_job", {job: mock_job, error: mock_error})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_failed", metric_name: "jobs_failed")
        )
      end

      it "subscribes to discard.active_job" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        ActiveSupport::Notifications.instrument("discard.active_job", {job: mock_job})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_discarded", metric_name: "jobs_discarded")
        )
      end

      it "passes QueueEventBuffer instance" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: mock_job})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(buffer: SolidObserver::QueueEventBuffer.instance)
        )
      end

      it "passes ActiveSupport::Notifications::Event object" do
        described_class.subscribe!

        mock_job = double("Job", job_id: "123", queue_name: "default").as_null_object
        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: mock_job})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call) do |args|
          expect(args[:event]).to be_a(ActiveSupport::Notifications::Event)
          expect(args[:event].payload[:job].job_id).to eq("123")
        end
      end
    end
  end

  describe "integration" do
    it "records events end-to-end" do
      allow(SolidObserver.config).to receive(:observe_queue).and_return(true)
      allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      allow(SolidObserver::Services::RecordEvent).to receive(:call).and_call_original

      buffer = SolidObserver::QueueEventBuffer.instance
      allow(buffer).to receive(:push)
      allow(SolidObserver::QueueMetric).to receive(:increment)

      described_class.subscribe!

      mock_job = double("Job", job_id: "integration-test", queue_name: "default").as_null_object
      ActiveSupport::Notifications.instrument("perform.active_job", {job: mock_job})

      expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
        hash_including(
          event_type: "job_completed",
          metric_name: "jobs_completed",
          buffer: buffer
        )
      )
    end
  end

  describe ".unsubscribe!" do
    before do
      allow(SolidObserver.config).to receive(:observe_queue).and_return(true)
    end

    it "removes all subscriptions" do
      described_class.subscribe!
      expect(described_class.subscribed?).to be true

      described_class.unsubscribe!
      expect(described_class.subscribed?).to be false
    end

    it "is a no-op when called without prior subscribe" do
      expect { described_class.unsubscribe! }.not_to raise_error
      expect(described_class.subscribed?).to be false
    end
  end

  describe ".subscribed?" do
    before do
      allow(SolidObserver.config).to receive(:observe_queue).and_return(true)
    end

    it "returns true when subscribed" do
      described_class.subscribe!
      expect(described_class.subscribed?).to be true
    end

    it "returns false when not subscribed" do
      described_class.unsubscribe!
      expect(described_class.subscribed?).to be false
    end
  end

  describe "EVENTS constant" do
    it "lists all subscribed event names" do
      expect(described_class::EVENTS).to contain_exactly(
        "enqueue.active_job",
        "perform.active_job",
        "retry_stopped.active_job",
        "discard.active_job"
      )
    end
  end
end
