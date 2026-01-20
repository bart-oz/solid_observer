# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::RecordEvent do
  let(:event_payload) do
    {
      job: {
        job_id: "test-job-123",
        class_name: "TestJob",
        queue_name: "default",
        arguments: [1, 2, 3],
        executions: 1,
        enqueued_at: Time.current,
        priority: 10
      }
    }
  end

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

      it "includes metadata as JSON" do
        service.call

        expect(buffer).to have_received(:push).with(hash_including(
          metadata: be_a(String)
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

  describe "#build_event_data" do
    subject(:service) { described_class.new(event, event_type, buffer, metric_name) }

    it "includes correlation_id from resolver" do
      event_data = service.send(:build_event_data)

      expect(event_data[:correlation_id]).to eq("correlation-123")
      expect(SolidObserver::CorrelationIdResolver).to have_received(:resolve).with(event)
    end

    it "extracts job metadata correctly" do
      event_data = service.send(:build_event_data)
      metadata = JSON.parse(event_data[:metadata])

      expect(metadata["job_id"]).to eq("test-job-123")
      expect(metadata["job_class"]).to eq("TestJob")
      expect(metadata["queue_name"]).to eq("default")
      expect(metadata["arguments"]).to eq([1, 2, 3])
      expect(metadata["executions"]).to eq(1)
      expect(metadata["priority"]).to eq(10)
    end

    context "with exception data" do
      let(:exception_obj) { StandardError.new("Something went wrong") }
      let(:event_payload) do
        {
          job: {job_id: "test-job-123", class_name: "TestJob", queue_name: "default"},
          exception_object: exception_obj
        }
      end

      it "includes exception information" do
        event_data = service.send(:build_event_data)
        metadata = JSON.parse(event_data[:metadata])

        expect(metadata["exception_class"]).to eq("StandardError")
        expect(metadata["exception_message"]).to eq("Something went wrong")
      end
    end

    context "with minimal payload" do
      let(:event_payload) { {} }

      it "handles missing job data gracefully" do
        event_data = service.send(:build_event_data)
        metadata = JSON.parse(event_data[:metadata])

        expect(metadata).to eq({})
      end
    end
  end
end
