# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CorrelationIdResolver do
  let(:event) { double(payload: {}) }

  after { SolidObserver.reset_configuration! }

  describe ".resolve" do
    context "with custom generator" do
      it "uses generator when configured" do
        SolidObserver.configure do |config|
          config.correlation_id_generator = -> { "custom-trace-id" }
        end

        expect(described_class.resolve(event)).to eq("custom-trace-id")
      end

      it "falls back when generator raises exception" do
        SolidObserver.configure do |config|
          config.correlation_id_generator = -> { raise "boom" }
        end

        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/) # UUID pattern
      end

      it "falls back when generator returns nil" do
        SolidObserver.configure do |config|
          config.correlation_id_generator = -> {}
        end

        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/) # UUID pattern
      end
    end

    context "with job event" do
      let(:job) { double(job_id: "job-123") }
      let(:event) { double(payload: {job: job}) }

      it "extracts job_id from payload" do
        expect(described_class.resolve(event)).to eq("job-123")
      end

      it "falls back to UUID when job is nil" do
        event = double(payload: {job: nil})
        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/)
      end

      it "falls back to UUID when job_id is nil" do
        job = double(job_id: nil)
        event = double(payload: {job: job})
        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/)
      end

      it "falls back to UUID when job_id is empty string" do
        job = double(job_id: "")
        event = double(payload: {job: job})
        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/)
      end
    end

    context "with thread-local correlation" do
      before { Thread.current[:solid_observer_correlation_id] = "request-456" }
      after { Thread.current[:solid_observer_correlation_id] = nil }

      it "uses thread-local value" do
        expect(described_class.resolve(event)).to eq("request-456")
      end

      it "handles empty string" do
        Thread.current[:solid_observer_correlation_id] = ""
        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/)
      end
    end

    context "with no correlation source" do
      it "generates UUID" do
        result = described_class.resolve(event)
        expect(result).to match(/\A[a-f0-9-]{36}\z/)
      end

      it "generates unique UUIDs" do
        result1 = described_class.resolve(event)
        result2 = described_class.resolve(event)
        expect(result1).not_to eq(result2)
      end
    end

    context "with fallback priority" do
      let(:job) { double(job_id: "job-789") }
      let(:event) { double(payload: {job: job}) }

      before { Thread.current[:solid_observer_correlation_id] = "request-999" }
      after { Thread.current[:solid_observer_correlation_id] = nil }

      it "prefers custom generator over job_id" do
        SolidObserver.configure do |config|
          config.correlation_id_generator = -> { "custom-priority" }
        end

        expect(described_class.resolve(event)).to eq("custom-priority")
      end

      it "prefers job_id over thread-local" do
        expect(described_class.resolve(event)).to eq("job-789")
      end

      it "uses thread-local when job_id is missing" do
        event = double(payload: {})
        expect(described_class.resolve(event)).to eq("request-999")
      end
    end
  end
end
