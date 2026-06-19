# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver storages page", type: :request do
  before(:all) do
    connection = SolidObserver::CacheEvent.connection

    next if connection.table_exists?(:solid_observer_cache_events)

    connection.create_table :solid_observer_cache_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.boolean :hit
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
    end
  end

  before(:all) do
    connection = ActiveRecord::Base.connection

    next if connection.table_exists?(:solid_cache_entries)

    connection.create_table :solid_cache_entries do |t|
      t.string :key
      t.text :value
    end
  end

  before(:all) do
    connection = SolidObserver::CableEvent.connection

    next if connection.table_exists?(:solid_observer_cable_events)

    connection.create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false, limit: 64
      t.datetime :recorded_at, null: false
    end
  end

  before(:all) do
    connection = ActiveRecord::Base.connection

    next if connection.table_exists?(:solid_cable_messages)

    connection.create_table :solid_cable_messages do |t|
      t.string :channel
      t.text :payload
      t.datetime :created_at
    end
  end

  around do |example|
    previous_layout = SolidObserver::StoragesController.send(:_layout)
    SolidObserver::StoragesController.layout false
    example.run
  ensure
    SolidObserver::StoragesController.layout previous_layout
  end

  before do
    SolidObserver::StoragesController.prepend_view_path(SolidObserver::Engine.root.join("app/views"))

    stub_const("SolidCache", Module.new)
    stub_const("SolidCache::Entry", Class.new(ActiveRecord::Base) do
      self.table_name = "solid_cache_entries"
    end)

    stub_const("SolidCable", Module.new)
    stub_const("SolidCable::Message", Class.new(ActiveRecord::Base) do
      self.table_name = "solid_cable_messages"
    end)

    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = false
    SolidObserver.config.observe_cache = true
    SolidObserver.config.observe_cable = true
    SolidObserver.config.storage_mode = :persistence

    allow(SolidObserver::StorageInfo).to receive(:recent).with(20).and_return([])

    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all
    SolidCable::Message.delete_all
  end

  after { SolidObserver.reset_configuration! }

  def call_action(path = "/solid_observer/storage")
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    status, headers, body = SolidObserver::StoragesController.action(:show).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  it "keeps the storages page request successful when SolidCache metrics raise PostgreSQL-style TypeError" do
    allow(SolidCache::Entry).to receive(:count).and_raise(TypeError, "no implicit conversion of nil into String")

    status, _headers, body = call_action

    expect(status).to eq(200)
    expect(body).to include("Storage")
    expect(body).to include("Component health")
    expect(body).to include("SolidCache")
    expect(body).to include("Storage unavailable")
    expect(body).not_to include("TypeError")
  end

  it "renders Solid Cable and Cable observer cards when cable observation is enabled" do
    status, _headers, body = call_action

    expect(status).to eq(200)
    expect(body).to include("Solid Cable messages")
    expect(body).to include("SolidObserver Cable telemetry")
    expect(body).to include("Available")
  end

  it "keeps the storages page request successful when SolidCable metrics raise PostgreSQL-style TypeError" do
    allow(SolidCable::Message).to receive(:count).and_raise(TypeError, "no implicit conversion of nil into String")

    status, _headers, body = call_action

    expect(status).to eq(200)
    expect(body).to include("Solid Cable messages")
    expect(body).to include("Storage unavailable")
    expect(body).not_to include("TypeError")
  end

  it "labels solid_cable history rows as messages in the Recent Snapshots table" do
    snapshot = double(
      "SolidObserver::StorageInfo",
      component: "solid_cable",
      db_size_bytes: 1024,
      event_count: 5,
      recorded_at: Time.current
    )
    allow(SolidObserver::StorageInfo).to receive(:recent).with(20).and_return([snapshot])

    _status, _headers, body = call_action

    expect(body).to include("Solid Cable messages")
    expect(body).to include("5 messages")
  end

  it "labels cable_observer history rows as SolidObserver Cable telemetry in the Recent Snapshots table" do
    snapshot = double(
      "SolidObserver::StorageInfo",
      component: "cable_observer",
      db_size_bytes: 2048,
      event_count: 10,
      recorded_at: Time.current
    )
    allow(SolidObserver::StorageInfo).to receive(:recent).with(20).and_return([snapshot])

    _status, _headers, body = call_action

    expect(body).to include("SolidObserver Cable telemetry")
    expect(body).to include("10 observer events")
  end
end
