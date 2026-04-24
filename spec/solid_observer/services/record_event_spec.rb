# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::RecordEvent do
  let(:job_obj) do
    double(
      "active_job_instance",
      job_id: "test-job-123",
      class: double("job_class", name: "TestJob"),
      queue_name: "default",
      executions: 1,
      enqueued_at: Time.current,
      priority: 10
    )
  end
  let(:event_payload) { {job: job_obj} }

  let(:event) do
    double(
      duration: 150.0,
      payload: event_payload
    )
  end

  let(:buffer) { instance_double(SolidObserver::QueueEventBuffer) }
  let(:event_type) { "job_completed" }
  let(:metric_name) { "jobs_completed" }

  before do
    allow(buffer).to receive(:push)
    allow(SolidObserver::QueueMetric).to receive(:increment)
    allow(SolidObserver::CorrelationIdResolver).to receive(:resolve).and_return("correlation-123")
  end

  describe ".call" do
    it "creates an instance and calls #call" do
      service_instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(service_instance)
      allow(service_instance).to receive(:call)

      described_class.call(
        event: event,
        event_type: event_type,
        buffer: buffer,
        metric_name: metric_name
      )

      expect(described_class).to have_received(:new).with(event, event_type, buffer, metric_name)
      expect(service_instance).to have_received(:call)
    end
  end

  describe "#call" do
    subject(:service) { described_class.new(event, event_type, buffer, metric_name) }

    context "when sampling allows recording" do
      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      end

      it "pushes event data to buffer" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          event_type: "job_completed",
          correlation_id: "correlation-123",
          duration: 150.0,
          recorded_at: be_a(Time)
        ))
      end

      it "includes job fields in metadata as JSON" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          job_class: "TestJob",
          queue_name: "default",
          metadata: satisfy { |m|
            JSON.parse(m).slice("job_id", "executions", "priority") == {
              "job_id" => "test-job-123",
              "executions" => 1,
              "priority" => 10
            }
          }
        ))
      end

      it "does not store job arguments in metadata" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          metadata: satisfy { |m| !JSON.parse(m).key?("arguments") }
        ))
      end

      it "increments the metric" do
        current_time = Time.current
        allow(Time).to receive(:current).and_return(current_time)

        service.call

        expect(SolidObserver::QueueMetric).to have_received(:increment).with(
          metric: "jobs_completed",
          period: current_time.beginning_of_hour
        )
      end
    end

    context "with exception data in payload" do
      let(:exception_job) do
        double(
          "active_job_instance",
          job_id: "test-job-123",
          class: double("job_class", name: "TestJob"),
          queue_name: "default",
          executions: 1,
          enqueued_at: nil,
          priority: nil
        )
      end
      let(:event_payload) do
        {
          job: exception_job,
          exception_object: StandardError.new("Something went wrong")
        }
      end

      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      end

      it "includes exception class and message in metadata" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          metadata: satisfy { |m|
            parsed = JSON.parse(m)
            parsed["exception_class"] == "StandardError" && parsed["exception_message"] == "Something went wrong"
          }
        ))
      end
    end

    context "with hash-shaped payload[:job] (adapter fallback)" do
      let(:event_payload) do
        {
          job: {
            job_id: "hash-job-456",
            class_name: "HashJob",
            queue_name: "batch",
            executions: 2,
            enqueued_at: nil,
            priority: nil
          }
        }
      end

      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      end

      it "extracts job_class and queue_name from hash keys" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          job_class: "HashJob",
          queue_name: "batch"
        ))
      end

      it "does not store arguments" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          metadata: satisfy { |m| !JSON.parse(m).key?("arguments") }
        ))
      end
    end

    context "with minimal empty payload" do
      let(:event_payload) { {} }

      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
      end

      it "handles missing job data gracefully" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          metadata: satisfy { |m| JSON.parse(m) == {} }
        ))
      end
    end

    context "when sampling rejects recording" do
      before do
        allow(service).to receive(:rand).and_return(0.9)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(0.5)
      end

      it "does not push to buffer" do
        service.call

        expect(buffer).not_to have_received(:push)
      end

      it "does not increment metric" do
        service.call

        expect(SolidObserver::QueueMetric).not_to have_received(:increment)
      end
    end

    context "when buffer push fails" do
      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
        allow(buffer).to receive(:push).and_raise(StandardError, "Buffer error")
        allow(Rails).to receive(:logger).and_return(double(warn: nil))
      end

      it "logs the error" do
        service.call

        expect(Rails.logger).to have_received(:warn).with(
          "[SolidObserver] Event recording failed: Buffer error"
        )
      end

      it "does not raise the error" do
        expect { service.call }.not_to raise_error
      end
    end

    context "when in realtime mode" do
      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
        allow(SolidObserver.config).to receive(:persistence_mode?).and_return(false)
      end

      it "does not increment metric" do
        service.call

        expect(SolidObserver::QueueMetric).not_to have_received(:increment)
      end

      it "still pushes event to buffer" do
        service.call

        expect(buffer).to have_received(:push)
      end
    end

    context "when metric increment fails" do
      before do
        allow(service).to receive(:rand).and_return(0.5)
        allow(SolidObserver.config).to receive(:sampling_rate).and_return(1.0)
        allow(SolidObserver::QueueMetric).to receive(:increment).and_raise(StandardError, "Metric error")
        allow(Rails).to receive(:logger).and_return(double(warn: nil))
      end

      it "still pushes to buffer" do
        service.call

        expect(buffer).to have_received(:push)
      end

      it "logs the metric error" do
        service.call

        expect(Rails.logger).to have_received(:warn).with(
          "[SolidObserver] Metric increment failed: Metric error"
        )
      end
    end
  end
end
