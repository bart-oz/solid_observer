# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Real-time mode" do
  after { SolidObserver.reset_configuration! }

  before do
    SolidObserver.config.storage_mode = :realtime
  end

  describe "configuration" do
    it "reports realtime mode" do
      expect(SolidObserver.config.realtime_mode?).to be true
      expect(SolidObserver.config.persistence_mode?).to be false
    end
  end

  describe "QueueEventBuffer" do
    subject(:buffer) { SolidObserver::QueueEventBuffer.instance }

    before { buffer.clear }
    after { buffer.clear }

    it "does not buffer events" do
      buffer.push({event_type: "job_enqueued", recorded_at: Time.current})

      expect(buffer.size).to eq(0)
    end
  end

  describe "RecordEvent" do
    let(:event) do
      double(duration: 100.0, payload: {job: {job_id: "123", class_name: "TestJob", queue_name: "default"}})
    end
    let(:buffer) { instance_double(SolidObserver::QueueEventBuffer) }

    before do
      allow(buffer).to receive(:push)
      allow(SolidObserver::CorrelationIdResolver).to receive(:resolve).and_return("test-id")
    end

    it "does not increment metrics" do
      expect(SolidObserver::QueueMetric).not_to receive(:increment)

      SolidObserver::Services::RecordEvent.call(
        event: event,
        event_type: "job_completed",
        buffer: buffer,
        metric_name: "jobs_completed"
      )
    end
  end

  describe "CleanupStorage" do
    it "returns 0 without performing any operations" do
      expect(SolidObserver::QueueEvent).not_to receive(:transaction)

      result = SolidObserver::Services::CleanupStorage.call

      expect(result).to eq(0)
    end
  end

  describe "CLI::Storage" do
    it "shows real-time mode message" do
      output = capture_stdout { SolidObserver::CLI::Storage.new.call }

      expect(output).to include("not available in real-time mode")
    end
  end

  describe "QueueStats" do
    it "still works (queries SolidQueue directly)" do
      allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false)

      stats = SolidObserver::QueueStats.snapshot

      expect(stats).to include(available: false)
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
