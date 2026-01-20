# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Subscriber do
  before do
    allow(SolidObserver::Services::RecordEvent).to receive(:call)
  end

  after do
    ActiveSupport::Notifications.unsubscribe("enqueue.active_job")
    ActiveSupport::Notifications.unsubscribe("perform.active_job")
    ActiveSupport::Notifications.unsubscribe("retry_stopped.active_job")
    ActiveSupport::Notifications.unsubscribe("discard.active_job")
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

        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_enqueued", metric_name: "jobs_enqueued")
        )
      end

      it "subscribes to perform.active_job" do
        described_class.subscribe!

        ActiveSupport::Notifications.instrument("perform.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_completed", metric_name: "jobs_completed")
        )
      end

      it "subscribes to retry_stopped.active_job" do
        described_class.subscribe!

        ActiveSupport::Notifications.instrument("retry_stopped.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_failed", metric_name: "jobs_failed")
        )
      end

      it "subscribes to discard.active_job" do
        described_class.subscribe!

        ActiveSupport::Notifications.instrument("discard.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(event_type: "job_discarded", metric_name: "jobs_discarded")
        )
      end

      it "passes QueueEventBuffer instance" do
        described_class.subscribe!

        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call).with(
          hash_including(buffer: SolidObserver::QueueEventBuffer.instance)
        )
      end

      it "passes ActiveSupport::Notifications::Event object" do
        described_class.subscribe!

        ActiveSupport::Notifications.instrument("enqueue.active_job", {job: {job_id: "123"}})

        expect(SolidObserver::Services::RecordEvent).to have_received(:call) do |args|
          expect(args[:event]).to be_a(ActiveSupport::Notifications::Event)
          expect(args[:event].payload[:job][:job_id]).to eq("123")
        end
      end
    end
  end

  describe "integration" do
    before do
      allow(SolidObserver::Services::RecordEvent).to receive(:call).and_call_original
    end

    it "records events end-to-end" do
      allow(SolidObserver.config).to receive(:observe_queue).and_return(true)
      allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)

      buffer = SolidObserver::QueueEventBuffer.instance
      allow(buffer).to receive(:push)
      allow(SolidObserver::QueueMetric).to receive(:increment)
      allow(SolidObserver::CorrelationIdResolver).to receive(:resolve).and_return("test-correlation-id")

      described_class.subscribe!

      ActiveSupport::Notifications.instrument("perform.active_job", {job: {job_id: "integration-test"}})

      expect(buffer).to have_received(:push).once do |event_data|
        expect(event_data[:event_type]).to eq("job_completed")
        expect(event_data[:correlation_id]).to eq("test-correlation-id")
      end
    end
  end
end
