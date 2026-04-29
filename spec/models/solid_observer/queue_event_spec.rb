# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver::QueueEvent" do
  after { SolidObserver.reset_configuration! }

  it "model file exists" do
    model_path = File.join(__dir__, "../../../app/models/solid_observer/queue_event.rb")
    expect(File.exist?(model_path)).to be true
  end

  it "inherits from BaseEvent" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/queue_event.rb"))
    expect(model_content).to include("< BaseEvent")
  end

  it "inherits database connection from BaseEvent" do
    expect(SolidObserver::QueueEvent.superclass).to eq(SolidObserver::BaseEvent)
  end

  it "uses solid_observer_queue_events table" do
    expect(SolidObserver::QueueEvent.table_name).to eq("solid_observer_queue_events")
  end

  describe "distinct filter scopes" do
    before(:all) do
      connection = SolidObserver::QueueEvent.connection
      next if connection.table_exists?(:solid_observer_queue_events)

      connection.create_table :solid_observer_queue_events do |t|
        t.string :event_type, null: false, limit: 50
        t.string :job_class, limit: 100
        t.string :queue_name, limit: 50
        t.datetime :recorded_at, null: false
      end
    end

    before do
      SolidObserver.config.event_retention = 30.days
      SolidObserver::QueueEvent.delete_all
    end

    it "uses a default distinct filter limit of 500" do
      expect(SolidObserver::QueueEvent::DISTINCT_FILTER_LIMIT).to eq(500)
    end

    it "returns distinct sorted job classes within retention and without nils" do
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "ZJob", queue_name: "default", recorded_at: 1.day.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "AJob", queue_name: "default", recorded_at: 2.days.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "AJob", queue_name: "urgent", recorded_at: 3.days.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: nil, queue_name: "default", recorded_at: 1.day.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "OldJob", queue_name: "default", recorded_at: 40.days.ago)

      expect(SolidObserver::QueueEvent.distinct_job_classes).to eq(%w[AJob ZJob])
    end

    it "returns distinct sorted queue names within retention and without nils" do
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "MyJob", queue_name: "urgent", recorded_at: 1.day.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "MyJob", queue_name: "default", recorded_at: 2.days.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "MyJob", queue_name: "default", recorded_at: 3.days.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "MyJob", queue_name: nil, recorded_at: 1.day.ago)
      SolidObserver::QueueEvent.create!(event_type: "job_enqueued", job_class: "MyJob", queue_name: "archive", recorded_at: 40.days.ago)

      expect(SolidObserver::QueueEvent.distinct_queue_names).to eq(%w[default urgent])
    end

    it "applies DISTINCT_FILTER_LIMIT to job classes" do
      stub_const("SolidObserver::QueueEvent::DISTINCT_FILTER_LIMIT", 3)
      5.times do |index|
        SolidObserver::QueueEvent.create!(
          event_type: "job_enqueued",
          job_class: "Job#{index}",
          queue_name: "default",
          recorded_at: 1.day.ago
        )
      end

      expect(SolidObserver::QueueEvent.distinct_job_classes.count).to eq(3)
    end

    it "applies DISTINCT_FILTER_LIMIT to queue names" do
      stub_const("SolidObserver::QueueEvent::DISTINCT_FILTER_LIMIT", 3)
      5.times do |index|
        SolidObserver::QueueEvent.create!(
          event_type: "job_enqueued",
          job_class: "MyJob",
          queue_name: "queue_#{index}",
          recorded_at: 1.day.ago
        )
      end

      expect(SolidObserver::QueueEvent.distinct_queue_names.count).to eq(3)
    end
  end

  describe "throughput counters" do
    before(:all) do
      connection = SolidObserver::QueueEvent.connection
      next if connection.table_exists?(:solid_observer_queue_events)

      connection.create_table :solid_observer_queue_events do |t|
        t.string :event_type, null: false, limit: 50
        t.string :job_class, limit: 100
        t.string :queue_name, limit: 50
        t.datetime :recorded_at, null: false
      end
    end

    before { SolidObserver::QueueEvent.delete_all }

    describe ".performed_count_last" do
      it "counts completed events within the provided window" do
        travel_to(Time.utc(2026, 1, 21, 12, 0, 0)) do
          SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 20.minutes.ago)
          SolidObserver::QueueEvent.create!(event_type: "job_completed", recorded_at: 2.hours.ago)
          SolidObserver::QueueEvent.create!(event_type: "job_failed", recorded_at: 10.minutes.ago)

          expect(SolidObserver::QueueEvent.performed_count_last(1.hour)).to eq(1)
        end
      end
    end

    describe ".failed_count_last" do
      it "counts failed events within the provided window" do
        travel_to(Time.utc(2026, 1, 21, 12, 0, 0)) do
          SolidObserver::QueueEvent.create!(event_type: "job_failed", recorded_at: 6.hours.ago)
          SolidObserver::QueueEvent.create!(event_type: "job_failed", recorded_at: 30.hours.ago)
          SolidObserver::QueueEvent.create!(event_type: "job_discarded", recorded_at: 2.hours.ago)

          expect(SolidObserver::QueueEvent.failed_count_last(24.hours)).to eq(1)
        end
      end
    end

    describe ".enqueue_rate_per_minute" do
      it "returns jobs per minute rounded to one decimal place" do
        travel_to(Time.utc(2026, 1, 21, 12, 0, 0)) do
          12.times { SolidObserver::QueueEvent.create!(event_type: "job_enqueued", recorded_at: 2.minutes.ago) }
          SolidObserver::QueueEvent.create!(event_type: "job_enqueued", recorded_at: 10.minutes.ago)

          expect(SolidObserver::QueueEvent.enqueue_rate_per_minute(window: 5.minutes)).to eq(2.4)
        end
      end

      it "returns 0.0 when there are no enqueues in the window" do
        travel_to(Time.utc(2026, 1, 21, 12, 0, 0)) do
          SolidObserver::QueueEvent.create!(event_type: "job_enqueued", recorded_at: 10.minutes.ago)

          expect(SolidObserver::QueueEvent.enqueue_rate_per_minute(window: 5.minutes)).to eq(0.0)
        end
      end
    end
  end
end
