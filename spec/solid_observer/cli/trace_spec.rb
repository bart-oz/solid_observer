# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Trace do
  let(:trace_cli) { described_class.new }

  after { SolidObserver.reset_configuration! }

  describe "#call" do
    context "when in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "prints the realtime mode message" do
        output = capture_stdout { trace_cli.call(correlation_id: "abc") }

        expect(output).to include("Trace unavailable in realtime mode.")
      end
    end

    context "when the trace is empty" do
      before do
        result = SolidObserver::Queries::TraceQuery::Result.new(rows: [], unavailable_components: [])
        query = instance_double(SolidObserver::Queries::TraceQuery, call: result)
        allow(SolidObserver::Queries::TraceQuery).to receive(:new).and_return(query)
      end

      it "prints a no-events message" do
        output = capture_stdout { trace_cli.call(correlation_id: "missing") }

        expect(output).to include("No events found for correlation_id: missing")
      end
    end

    context "when the trace has rows" do
      let(:rows) do
        [
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 1), component: :queue, event_type: "job_completed", duration: 1.234, job_class: "TestJob", queue_name: "default", id: 1},
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 2), component: :cache, event_type: "cache_error", duration: 0.5, hit: true, error_class: "Redis::TimeoutError", id: 2},
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 3), component: :cable, event_type: "broadcast", duration: 0.2, channel_class: "ChatChannel", error_class: "ActionCableError", collapsed_count: 5, id: 3}
        ]
      end

      before do
        result = SolidObserver::Queries::TraceQuery::Result.new(rows: rows, unavailable_components: [])
        query = instance_double(SolidObserver::Queries::TraceQuery, call: result)
        allow(SolidObserver::Queries::TraceQuery).to receive(:new).and_return(query)
      end

      it "prints the trace table with headers and rows" do
        output = capture_stdout { trace_cli.call(correlation_id: "abc") }

        expect(output).to include("Time")
        expect(output).to include("Component")
        expect(output).to include("Event")
        expect(output).to include("Details")
        expect(output).to include("queue")
        expect(output).to include("cache")
        expect(output).to include("cable")
        expect(output).to include("TestJob")
        expect(output).to include("ChatChannel")
        expect(output).to include("Redis::TimeoutError")
        expect(output).to include("ActionCableError")
      end
    end

    context "when a component is unavailable" do
      let(:rows) do
        [
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 1), component: :queue, event_type: "job_completed", duration: 1.0, job_class: "TestJob", queue_name: "default", id: 1}
        ]
      end

      before do
        result = SolidObserver::Queries::TraceQuery::Result.new(rows: rows, unavailable_components: [:cache])
        query = instance_double(SolidObserver::Queries::TraceQuery, call: result)
        allow(SolidObserver::Queries::TraceQuery).to receive(:new).and_return(query)
      end

      it "prints the unavailable component" do
        output = capture_stdout { trace_cli.call(correlation_id: "abc") }

        expect(output).to include("cache unavailable")
      end
    end

    context "with PII-safe rows" do
      let(:rows) do
        [
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 1), component: :cache, event_type: "cache_hit", duration: 0.5, hit: true, id: 1},
          {recorded_at: Time.utc(2026, 1, 1, 12, 0, 2), component: :cable, event_type: "broadcast", duration: 0.2, channel_class: "ChatChannel", collapsed_count: 3, id: 2}
        ]
      end

      before do
        result = SolidObserver::Queries::TraceQuery::Result.new(rows: rows, unavailable_components: [])
        query = instance_double(SolidObserver::Queries::TraceQuery, call: result)
        allow(SolidObserver::Queries::TraceQuery).to receive(:new).and_return(query)
      end

      it "does not expose digests or unsafe metadata in output" do
        output = capture_stdout { trace_cli.call(correlation_id: "abc") }

        expect(output).not_to include("key_digest")
        expect(output).not_to include("broadcasting_digest")
        expect(output).not_to include("metadata")
        expect(output).not_to include("error_message")
      end
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
