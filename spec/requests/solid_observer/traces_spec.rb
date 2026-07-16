# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver traces", type: :request do
  before(:all) do
    reset_trace_tables
  end

  around do |example|
    previous_layout = SolidObserver::TracesController.send(:_layout)
    SolidObserver::TracesController.layout false
    example.run
  ensure
    SolidObserver::TracesController.layout previous_layout
  end

  before do
    ensure_engine_view_path!
    install_path_helpers!

    stub_const("SolidCache", Module.new)
    stub_const("SolidCable", Module.new)

    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = true
    SolidObserver.config.observe_cache = true
    SolidObserver.config.observe_cable = true
    SolidObserver.config.storage_mode = :persistence

    SolidObserver::QueueEvent.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidObserver::CableEvent.delete_all
  end

  after { SolidObserver.reset_configuration! }

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    current_paths = SolidObserver::TracesController.view_paths.map(&:to_s)
    return if current_paths.include?(engine_views)

    SolidObserver::TracesController.prepend_view_path(engine_views)
  end

  def install_path_helpers!
    controller_class = SolidObserver::TracesController
    return if controller_class.method_defined?(:trace_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :storage_path,
        :cache_dashboard_path,
        :cache_operations_path,
        :cable_dashboard_path,
        :trace_path,
        :live_poll_script_path

      def root_path
        "/solid_observer"
      end

      def jobs_path
        "/solid_observer/jobs"
      end

      def events_path
        "/solid_observer/events"
      end

      def storage_path
        "/solid_observer/storage"
      end

      def cache_dashboard_path
        "/solid_observer/cache"
      end

      def cache_operations_path
        "/solid_observer/cache/controls"
      end

      def cable_dashboard_path
        "/solid_observer/cable"
      end

      def trace_path(id)
        "/solid_observer/traces/#{id}"
      end

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end
    end
  end

  def call_action(path, id: nil)
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    env["action_dispatch.request.path_parameters"] = {controller: "solid_observer/traces", action: "show", id: id} if id
    status, headers, body = SolidObserver::TracesController.action(:show).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  def reset_trace_tables
    connection = SolidObserver::BaseRecord.connection
    reset_table(connection, :solid_observer_queue_events) do |t|
      t.string :event_type, null: false
      t.string :job_class
      t.string :queue_name
      t.string :correlation_id, limit: 64
      t.text :metadata
      t.float :duration
      t.datetime :recorded_at, null: false
    end
    reset_table(connection, :solid_observer_cache_events) do |t|
      t.string :event_type, null: false
      t.string :key_digest, null: false
      t.boolean :hit
      t.float :duration
      t.string :error_class
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
    reset_table(connection, :solid_observer_cable_events) do |t|
      t.string :event_type, null: false
      t.string :channel_class
      t.string :broadcasting_digest
      t.float :duration
      t.string :error_class
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
  end

  def reset_table(connection, table, &block)
    connection.drop_table(table, if_exists: true)
    connection.create_table(table, &block)
  end

  it "defines the trace show route" do
    routes_source = File.read(File.expand_path("../../../config/routes.rb", __dir__))

    expect(routes_source).to include("resources :traces, only: [:show]")
  end

  it "renders the trace timeline with newest-100 cap and component badges" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    travel_to(fixed_time) do
      create_queue_event(correlation_id: "trace-123", recorded_at: fixed_time - 2.seconds, job_class: "MailDigestJob", queue_name: "default", duration: 0.041)
      create_cache_event(correlation_id: "trace-123", recorded_at: fixed_time - 1.second, key_digest: "abc123", hit: true, duration: 0.003)
      create_cable_event(correlation_id: "trace-123", recorded_at: fixed_time, channel_class: "NotificationsChannel", broadcasting_digest: "bd1", duration: 0.012)

      status, _headers, body = call_action("/solid_observer/traces/trace-123", id: "trace-123")

      expect(status).to eq(200)
      expect(body).to include("Trace")
      expect(body).to include("trace-123")
      expect(body).to include("Showing newest 3 events (maximum 100)")
      expect(body).to include("Trace timeline for correlation ID trace-123")
      expect(body).to include("Queue")
      expect(body).to include("Cache")
      expect(body).to include("Cable")
      expect(body).to include("MailDigestJob")
      expect(body).to include("NotificationsChannel")
      expect(body).to include("job=MailDigestJob queue=default")
      expect(body).to include("hit=true")
      expect(body).to include("channel=NotificationsChannel")
    end
  end

  it "renders rows in chronological order" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    create_queue_event(correlation_id: "chrono", recorded_at: fixed_time + 2.seconds, job_class: "LateJob", queue_name: "default", duration: 0.1)
    create_queue_event(correlation_id: "chrono", recorded_at: fixed_time, job_class: "EarlyJob", queue_name: "default", duration: 0.1)

    status, _headers, body = call_action("/solid_observer/traces/chrono", id: "chrono")

    expect(status).to eq(200)
    expect(body).to include("EarlyJob")
    expect(body).to include("LateJob")
    early_position = body.index("EarlyJob")
    late_position = body.index("LateJob")
    expect(early_position).to be < late_position
  end

  it "renders an empty state when the correlation ID has no rows" do
    status, _headers, body = call_action("/solid_observer/traces/no-such-id", id: "no-such-id")

    expect(status).to eq(200)
    expect(body).to include("No events found for correlation ID no-such-id")
    expect(body).to include("The trace may have expired, not yet recorded, or belong to an unavailable component")
  end

  it "redirects to the dashboard in realtime mode" do
    SolidObserver.config.storage_mode = :realtime

    status, headers, _body = call_action("/solid_observer/traces/trace-123", id: "trace-123")

    expect(status).to eq(302)
    expect(headers["Location"]).to include("/solid_observer")
  end

  it "does not expose raw cache keys, digests, job arguments, payloads, metadata, or error messages" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    create_queue_event(correlation_id: "pii", recorded_at: fixed_time, job_class: "MailDigestJob", queue_name: "default", duration: 0.041, metadata: '{"args":["secret"]}')
    create_cache_event(correlation_id: "pii", recorded_at: fixed_time, key_digest: "secret-key-digest", hit: true, duration: 0.003, error_message: "secret cache error", metadata: '{"key":"secret-key"}')
    create_cable_event(correlation_id: "pii", recorded_at: fixed_time, channel_class: "NotificationsChannel", broadcasting_digest: "secret-broadcast-digest", duration: 0.012, error_message: "secret cable error", metadata: '{"payload":"secret-payload"}')

    _status, _headers, body = call_action("/solid_observer/traces/pii", id: "pii")

    expect(body).not_to include("secret-key")
    expect(body).not_to include("secret-key-digest")
    expect(body).not_to include("secret-broadcast-digest")
    expect(body).not_to include("secret cache error")
    expect(body).not_to include("secret cable error")
    expect(body).not_to include("secret-payload")
    expect(body).not_to include("args")
    expect(body).not_to include("payload")
    expect(body).not_to include("error_message")
    expect(body).not_to include("metadata")
    expect(body).to include("MailDigestJob")
    expect(body).to include("NotificationsChannel")
  end

  it "shows unavailable component names when a component cannot be read" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)
    create_queue_event(correlation_id: "unavailable", recorded_at: fixed_time, job_class: "MailDigestJob", queue_name: "default", duration: 0.041)

    bad_connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
    allow(bad_connection).to receive(:data_source_exists?).and_return(false)
    allow(SolidObserver::CacheEvent).to receive(:connection).and_return(bad_connection)

    _status, _headers, body = call_action("/solid_observer/traces/unavailable", id: "unavailable")

    expect(body).to include("Some components could not be read: cache")
    expect(body).to include("Showing available events only")
    expect(body).to include("MailDigestJob")
  end

  it "renders a trace link on queue event rows with a correlation ID" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    install_events_path_helpers!

    travel_to(fixed_time) do
      SolidObserver::QueueEvent.create!(
        event_type: "job_completed",
        job_class: "MailDigestJob",
        queue_name: "default",
        duration: 0.041,
        recorded_at: fixed_time,
        correlation_id: "queue-correlation"
      )

      previous_layout = SolidObserver::EventsController.send(:_layout)
      SolidObserver::EventsController.layout false
      SolidObserver::EventsController.prepend_view_path(SolidObserver::Engine.root.join("app/views"))
      env = Rack::MockRequest.env_for("/solid_observer/events", {"action_dispatch.routes" => SolidObserver::Engine.routes})
      status, _headers, body = SolidObserver::EventsController.action(:index).call(env)
      SolidObserver::EventsController.layout previous_layout
      response_body = +""
      body.each { |chunk| response_body << chunk }

      expect(status).to eq(200)
      expect(response_body).to include("Trace →")
      expect(response_body).to include('href="/solid_observer/traces/queue-correlation"')
    end
  end

  it "renders collapsed count for consecutive same-digest cable broadcasts" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    create_cable_event(correlation_id: "collapsed-cable", recorded_at: fixed_time, channel_class: "NotificationsChannel", broadcasting_digest: "same-digest", duration: 0.01)
    create_cable_event(correlation_id: "collapsed-cable", recorded_at: fixed_time + 1.second, channel_class: "NotificationsChannel", broadcasting_digest: "same-digest", duration: 0.02)

    _status, _headers, body = call_action("/solid_observer/traces/collapsed-cable", id: "collapsed-cable")

    expect(body).to include("collapsed=2")
  end

  it "renders the cable_summary branch when cable rows exceed the cap" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    51.times do |i|
      create_cable_event(
        correlation_id: "cable-cap",
        recorded_at: fixed_time + i.seconds,
        channel_class: "ChatChannel",
        broadcasting_digest: "digest-#{i}",
        duration: 0.001
      )
    end

    _status, _headers, body = call_action("/solid_observer/traces/cable-cap", id: "cable-cap")

    expect(body).to include("2 additional Cable broadcast events collapsed")
  end

  def create_queue_event(correlation_id:, recorded_at:, event_type: "job_completed", job_class: nil, queue_name: nil, duration: nil, metadata: nil)
    SolidObserver::QueueEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      job_class: job_class,
      queue_name: queue_name,
      duration: duration,
      metadata: metadata
    )
  end

  def create_cache_event(correlation_id:, recorded_at:, key_digest:, event_type: "cache_hit", hit: nil, error_class: nil, duration: nil, metadata: nil, error_message: nil)
    SolidObserver::CacheEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      key_digest: key_digest,
      hit: hit,
      error_class: error_class,
      duration: duration,
      metadata: metadata,
      error_message: error_message
    )
  end

  def create_cable_event(correlation_id:, recorded_at:, event_type: "broadcast", channel_class: nil, broadcasting_digest: nil, error_class: nil, duration: nil, metadata: nil, error_message: nil)
    SolidObserver::CableEvent.create!(
      correlation_id: correlation_id,
      recorded_at: recorded_at,
      event_type: event_type,
      channel_class: channel_class,
      broadcasting_digest: broadcasting_digest,
      error_class: error_class,
      duration: duration,
      metadata: metadata,
      error_message: error_message
    )
  end

  def install_events_path_helpers!
    controller_class = SolidObserver::EventsController
    controller_class.helper SolidObserver::ApplicationHelper
    return if controller_class.method_defined?(:trace_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :event_path,
        :storage_path,
        :cache_dashboard_path,
        :cable_dashboard_path,
        :trace_path,
        :live_poll_script_path

      def root_path
        "/solid_observer"
      end

      def jobs_path
        "/solid_observer/jobs"
      end

      def events_path
        "/solid_observer/events"
      end

      def event_path(id)
        "/solid_observer/events/#{id}"
      end

      def storage_path
        "/solid_observer/storage"
      end

      def cache_dashboard_path
        "/solid_observer/cache"
      end

      def cable_dashboard_path
        "/solid_observer/cable"
      end

      def trace_path(id)
        "/solid_observer/traces/#{id}"
      end

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end
    end
  end
end
