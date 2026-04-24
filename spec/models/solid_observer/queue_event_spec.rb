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
end
