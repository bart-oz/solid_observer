# frozen_string_literal: true

require "spec_helper"

RSpec.describe "Integration: Correlation ID propagation across job, cache, and cable", type: :integration do
  before(:all) do
    queue_connection = SolidObserver::QueueEvent.connection
    queue_connection.drop_table(:solid_observer_queue_events) if queue_connection.table_exists?(:solid_observer_queue_events)
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
    end

    cache_connection = SolidObserver::CacheEvent.connection
    cache_connection.drop_table(:solid_observer_cache_events) if cache_connection.table_exists?(:solid_observer_cache_events)
    cache_connection.create_table :solid_observer_cache_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.boolean :hit
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64

      t.index :recorded_at
      t.index :correlation_id, where: "correlation_id IS NOT NULL"
    end

    cable_connection = SolidObserver::CableEvent.connection
    cable_connection.drop_table(:solid_observer_cable_events) if cable_connection.table_exists?(:solid_observer_cable_events)
    cable_connection.create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :channel_class, limit: 255
      t.string :broadcasting_digest, limit: 64
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64

      t.index :recorded_at
      t.index :correlation_id, where: "correlation_id IS NOT NULL"
    end

    SolidObserver::QueueEvent.reset_column_information
    SolidObserver::CacheEvent.reset_column_information
    SolidObserver::CableEvent.reset_column_information
  end

  let(:test_job_class) do
    Class.new(ActiveJob::Base) do
      def perform
        ActiveSupport::Notifications.instrument("cache_read.active_support", key: "correlation:test", hit: true) {}
        ActiveSupport::Notifications.instrument("broadcast.action_cable", broadcasting: "chat:test") {}
      end
    end
  end

  before do
    stub_const("SolidCache", Module.new)
    stub_const("SolidCable", Module.new)

    SolidObserver.reset_configuration!
    SolidObserver.config.observe_queue = true
    SolidObserver.config.observe_cache = true
    SolidObserver.config.observe_cable = true
    SolidObserver.config.cache_sampling_rate = 1.0
    SolidObserver.config.cable_sampling_rate = 1.0
    SolidObserver.config.storage_mode = :persistence

    SolidObserver::Subscriber.subscribe!
    SolidObserver::CacheSubscriber.subscribe!
    SolidObserver::CableSubscriber.subscribe!

    SolidObserver::QueueEvent.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all
    SolidObserver::QueueEventBuffer.instance.clear
    SolidObserver::CacheEventBuffer.instance.clear
    SolidObserver::CableEventBuffer.instance.clear
  end

  after do
    SolidObserver::Subscriber.unsubscribe!
    SolidObserver::CacheSubscriber.unsubscribe!
    SolidObserver::CableSubscriber.unsubscribe!
    SolidObserver::QueueEventBuffer.instance.clear
    SolidObserver::CacheEventBuffer.instance.clear
    SolidObserver::CableEventBuffer.instance.clear
    SolidObserver.reset_configuration!
  end

  it "shares the job's correlation_id across queue, cache, and cable events" do
    job = test_job_class.new
    job.perform_now

    SolidObserver::QueueEventBuffer.instance.flush!
    SolidObserver::CacheEventBuffer.instance.flush!
    SolidObserver::CableEventBuffer.instance.flush!

    expect(SolidObserver::QueueEvent.count).to be >= 1
    expect(SolidObserver::CacheEvent.count).to eq(1)
    expect(SolidObserver::CableEvent.count).to eq(1)

    queue_event = SolidObserver::QueueEvent.find_by(event_type: "job_completed")
    cache_event = SolidObserver::CacheEvent.first
    cable_event = SolidObserver::CableEvent.first

    expect(queue_event).to be_present
    expect(queue_event.correlation_id).to eq(job.job_id)
    expect(cache_event.correlation_id).to eq(job.job_id)
    expect(cable_event.correlation_id).to eq(job.job_id)
    expect([queue_event, cache_event, cable_event].map(&:correlation_id).uniq.size).to eq(1)
  end

  it "does not leak correlation state to a subsequent job" do
    first_job = test_job_class.new
    second_job = test_job_class.new

    first_job.perform_now
    SolidObserver::QueueEventBuffer.instance.flush!
    SolidObserver::CacheEventBuffer.instance.flush!
    SolidObserver::CableEventBuffer.instance.flush!

    SolidObserver::QueueEvent.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all

    second_job.perform_now
    SolidObserver::QueueEventBuffer.instance.flush!
    SolidObserver::CacheEventBuffer.instance.flush!
    SolidObserver::CableEventBuffer.instance.flush!

    cache_event = SolidObserver::CacheEvent.first
    cable_event = SolidObserver::CableEvent.first

    expect(cache_event.correlation_id).to eq(second_job.job_id)
    expect(cable_event.correlation_id).to eq(second_job.job_id)
    expect(cache_event.correlation_id).not_to eq(first_job.job_id)
  end
end
