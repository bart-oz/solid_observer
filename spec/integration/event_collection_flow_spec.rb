# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Integration: Event Collection and Database Persistence", type: :integration do
  before(:all) do
    require_relative "../../db/solid_observer_migrate/20260115000001_create_solid_observer_queue_events"
    require_relative "../../db/solid_observer_migrate/20260115000002_create_solid_observer_metrics"

    queue_connection = SolidObserver::QueueEvent.connection

    if queue_connection.table_exists?(:solid_observer_queue_events)
      queue_connection.drop_table(:solid_observer_queue_events)
    end

    queue_connection.create_table :solid_observer_queue_events do |t|
      t.string :event_type, null: false, limit: 50
      t.string :job_class, limit: 100
      t.string :queue_name, limit: 50
      t.string :correlation_id, limit: 64
      t.text :metadata
      t.float :duration
      t.datetime :recorded_at, null: false

      t.index :recorded_at
      t.index :correlation_id, where: "correlation_id IS NOT NULL"
      t.index :event_type
      t.index :job_class
      t.index :queue_name
    end

    if ActiveRecord::Base.connection.table_exists?(:solid_observer_metrics)
      CreateSolidObserverMetrics.migrate(:down)
    end
    CreateSolidObserverMetrics.migrate(:up)
  end

  let(:buffer) { SolidObserver::QueueEventBuffer.instance }

  before do
    SolidObserver::QueueEvent.delete_all
    ActiveRecord::Base.connection.execute("DELETE FROM solid_observer_metrics")
    buffer.clear
  end

  describe "buffer and database integration" do
    it "pushes events to buffer and flushes to database" do
      buffer.push(
        event_type: "job_enqueued",
        job_class: "TestJob",
        queue_name: "default",
        correlation_id: "test-123",
        recorded_at: Time.current,
        duration: nil,
        metadata: {arguments: ["arg1"], priority: 10}.to_json
      )

      buffer.push(
        event_type: "job_completed",
        job_class: "TestJob",
        queue_name: "default",
        correlation_id: "test-123",
        recorded_at: Time.current,
        duration: 1.5,
        metadata: {duration: 1.5}.to_json
      )

      expect(buffer.size).to eq(2)

      buffer.flush!

      events = SolidObserver::QueueEvent.order(:recorded_at).to_a

      expect(events.length).to eq(2)
      expect(events[0].event_type).to eq("job_enqueued")
      expect(events[0].job_class).to eq("TestJob")
      expect(events[0].queue_name).to eq("default")
      expect(events[0].correlation_id).to eq("test-123")

      expect(events[1].event_type).to eq("job_completed")
      expect(events[1].job_class).to eq("TestJob")
      expect(events[1].correlation_id).to eq("test-123")
      expect(events[1].duration).to eq(1.5)
    end

    it "records metrics to database" do
      3.times do |i|
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_metrics (metric_name, value, period_start, period_type)
           VALUES ('jobs_enqueued', 1, datetime('now', '-#{i} hours'), 'hour')"
        )
      end

      metrics = ActiveRecord::Base.connection.execute(
        "SELECT * FROM solid_observer_metrics"
      ).to_a

      expect(metrics.length).to eq(3)
      expect(metrics.all? { |m| m["metric_name"] == "jobs_enqueued" }).to be true
    end

    it "handles JSON metadata serialization" do
      complex_metadata = {
        "arguments" => [{key: "value"}, "string_arg"],
        "nested" => {deep: {structure: "works"}},
        "array" => [1, 2, 3]
      }

      buffer.push(
        event_type: "job_enqueued",
        job_class: "ComplexJob",
        queue_name: "priority",
        correlation_id: "complex-456",
        recorded_at: Time.current,
        metadata: complex_metadata.to_json
      )

      buffer.flush!

      event = SolidObserver::QueueEvent.find_by(correlation_id: "complex-456")

      expect(event).to be_present
      expect(event.job_class).to eq("ComplexJob")
      expect(event.queue_name).to eq("priority")

      stored_metadata = JSON.parse(event.metadata)
      expect(stored_metadata["arguments"]).to eq([{"key" => "value"}, "string_arg"])
      expect(stored_metadata["nested"]).to eq({"deep" => {"structure" => "works"}})
    end

    it "maintains correlation across multiple events" do
      correlation_id = "job-#{SecureRandom.uuid}"

      %w[job_enqueued job_completed].each do |event_type|
        buffer.push(
          event_type: event_type,
          job_class: "CorrelatedJob",
          queue_name: "default",
          correlation_id: correlation_id,
          recorded_at: Time.current,
          metadata: {step: event_type}.to_json
        )
      end

      buffer.flush!

      events = SolidObserver::QueueEvent.where(correlation_id: correlation_id).order(:recorded_at).to_a

      expect(events.length).to eq(2)
      expect(events.map(&:correlation_id).uniq).to eq([correlation_id])
      expect(events.map(&:event_type)).to eq(%w[job_enqueued job_completed])
      expect(events.all? { |e| e.job_class == "CorrelatedJob" }).to be true
    end

    it "clears buffer after successful flush" do
      buffer.push(
        event_type: "job_enqueued",
        job_class: "TestJob",
        queue_name: "default",
        correlation_id: "clear-test",
        recorded_at: Time.current,
        metadata: {}.to_json
      )

      expect(buffer.size).to eq(1)
      buffer.flush!
      expect(buffer.size).to eq(0)
    end
  end
end
