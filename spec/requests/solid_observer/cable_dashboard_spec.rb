# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver cable dashboard", type: :request do
  before(:all) do
    connection = SolidObserver::CableMetric.connection

    next if connection.table_exists?(:solid_observer_cable_metrics)

    connection.create_table :solid_observer_cable_metrics do |t|
      t.datetime :period_start, null: false
      t.bigint :broadcasts_count, null: false, default: 0
      t.bigint :transmissions_count, null: false, default: 0
      t.bigint :confirmations_count, null: false, default: 0
      t.bigint :rejections_count, null: false, default: 0
      t.bigint :perform_actions_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
    end
  end

  before(:all) do
    connection = SolidObserver::CableEvent.connection

    next if connection.table_exists?(:solid_observer_cable_events)

    connection.create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :channel_class, limit: 255
      t.string :broadcasting_digest, limit: 64
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
    end
  end

  before do
    ensure_engine_view_path!
    install_path_helpers!

    stub_const("SolidCable", Module.new)
    stub_const("SolidCable::Message", Class.new)

    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = false
    SolidObserver.config.observe_cache = false
    SolidObserver.config.observe_cable = true
    SolidObserver.config.storage_mode = :persistence

    SolidObserver::CableMetric.delete_all
    SolidObserver::CableEvent.delete_all
  end

  after { SolidObserver.reset_configuration! }

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    current_paths = SolidObserver::CableDashboardController.view_paths.map(&:to_s)
    return if current_paths.include?(engine_views)

    SolidObserver::CableDashboardController.prepend_view_path(engine_views)
  end

  def install_path_helpers!
    controller_class = SolidObserver::CableDashboardController
    return if controller_class.method_defined?(:cable_dashboard_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :storage_path,
        :cache_dashboard_path,
        :cache_operations_path,
        :cable_dashboard_path,
        :trim_cable_operations_path,
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

      def trim_cable_operations_path
        "/solid_observer/cable/trim"
      end

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end
    end
  end

  def call_action(path)
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    status, headers, body = SolidObserver::CableDashboardController.action(:index).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  def default_storage_snapshots
    [
      {
        component: "cable_observer",
        label: "Cable telemetry",
        available: true,
        db_size_bytes: 12_288,
        event_count: 3,
        record_label: "observer events",
        recorded_at: Time.current,
        unavailable_reason: nil
      },
      {
        component: "solid_cable",
        label: "Solid Cable messages",
        available: true,
        db_size_bytes: 24_576,
        event_count: 100,
        record_label: "messages",
        recorded_at: Time.current,
        unavailable_reason: nil,
        trimmable_count: 10,
        oldest_message_age_seconds: 300
      }
    ]
  end

  def seed_cable_dashboard_data(fixed_time)
    SolidObserver::CableMetric.create!(
      period_start: fixed_time.beginning_of_minute,
      broadcasts_count: 100,
      transmissions_count: 90,
      confirmations_count: 80,
      rejections_count: 5,
      perform_actions_count: 10,
      errors_count: 2
    )
    SolidObserver::CableMetric.create!(
      period_start: 2.hours.ago.beginning_of_minute,
      broadcasts_count: 500,
      transmissions_count: 450,
      confirmations_count: 400,
      rejections_count: 50,
      perform_actions_count: 60,
      errors_count: 10
    )

    SolidObserver::CableEvent.create!(
      event_type: "broadcast",
      channel_class: "ChatChannel",
      broadcasting_digest: "abcdef1234567890",
      duration: 0.003,
      metadata: "{}",
      recorded_at: 5.minutes.ago
    )
    SolidObserver::CableEvent.create!(
      event_type: "transmit_subscription_rejection",
      channel_class: "AdminChannel",
      broadcasting_digest: "fedcba0987654321",
      duration: 0.001,
      metadata: "{}",
      recorded_at: 3.minutes.ago
    )
    SolidObserver::CableEvent.create!(
      event_type: "broadcast",
      channel_class: "ChatChannel",
      broadcasting_digest: "1122334455667788",
      duration: 0.02,
      error_class: "RuntimeError",
      error_message: "adapter internals should stay hidden",
      metadata: "{}",
      recorded_at: 2.minutes.ago
    )
    SolidObserver::CableEvent.create!(
      event_type: "broadcast",
      channel_class: "LegacyChannel",
      broadcasting_digest: "olddigest00000000",
      duration: 0.001,
      metadata: "{}",
      recorded_at: 2.hours.ago
    )
  end

  it "defines the cable overview route on CableDashboardController" do
    routes_source = File.read(File.expand_path("../../../config/routes.rb", __dir__))

    expect(routes_source).to include('get "cable", to: "cable_dashboard#index", as: :cable_dashboard')
  end

  it "renders activity trends, stability, and recent events for the selected range" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    travel_to(fixed_time) do
      seed_cable_dashboard_data(fixed_time)
      allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return(default_storage_snapshots)

      status, _headers, body = call_action("/solid_observer/cable?range=15m")

      expect(status).to eq(200)
      expect(body).to include("Cable overview")
      expect(body).to include("Available")
      expect(body).to include("Selected range: in last 15m · broadcasting names and payloads are never shown.")
      expect(body).to include('onchange="this.form.submit()"')
      expect(body).to include('<button type="submit" class="so-btn so-btn--refresh">Refresh data</button>')
      expect(body).to include("Summary in selected range")
      expect(body).to include("100")
      expect(body).to include("5%")
      expect(body).to include("10")
      expect(body).to include("36.0 KB")
      expect(body).to include("Cable telemetry + Solid Cable messages")
      expect(body).to include("Activity trends")
      expect(body).to include('data-so-spark="cable-broadcasts"')
      expect(body).to include('data-so-spark="cable-rejections"')
      expect(body).to match(/data-so-spark="cable-broadcasts".*?\u003cpolyline class="so-spark__line" points="[^"]+"/m)
      expect(body).to match(/data-so-spark="cable-rejections".*?\u003cpolyline class="so-spark__line" points="[^"]+"/m)
      expect(body).not_to include("No chart data in the selected range yet. Summary metrics still use bounded cable stats.")
      expect(body).to include('data-so-zone="cable-stability"')
      expect(body).to include("Stability")
      expect(body).to include("Critical")
      expect(body).to include("Recent Cable events")
      expect(body).to include("debug context only · broadcasting names and payloads are never shown")
      expect(body).to include("abcdef1234…")
      expect(body).to include("fedcba0987…")
      expect(body).to include("1122334455…")
      expect(body).to include("ChatChannel")
      expect(body).to include("AdminChannel")
      expect(body).not_to include("olddigest0000")
      expect(body).not_to include("adapter internals should stay hidden")
      expect(body).not_to include("{}")
    end
  end

  it "renders a guarded unavailable state and hides cable navigation when cable support is disabled" do
    SolidObserver.config.observe_cable = false

    status, _headers, body = call_action("/solid_observer/cable")

    expect(status).to eq(200)
    expect(body).to include("Cable dashboard unavailable")
    expect(body).to include("Unavailable")
    expect(body).to include("Cable dashboard is unavailable because Solid Cable support is disabled or not detected. Metrics are unavailable.")
    expect(body).not_to include("Refresh data")
    expect(body).not_to include("Summary in selected range")
    expect(body).not_to include("Recent Cable events")
    expect(body).not_to include('href="/solid_observer/cable"')
  end

  it "falls back to an empty recent-events state when cable event queries fail" do
    allow(SolidObserver::CableEvent).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("missing table"))

    status, _headers, body = call_action("/solid_observer/cable?range=15m")

    expect(status).to eq(200)
    expect(body).to include("No sampled cable events in the selected range yet. Broadcasts, rejections, and errors will appear here after Cable activity is recorded.")
    expect(body).not_to include("missing table")
  end

  it "keeps the cable dashboard request successful when the storage snapshot is unavailable" do
    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return([
      {
        component: "cable_observer",
        label: "Cable telemetry",
        available: false,
        db_size_bytes: nil,
        event_count: nil,
        record_label: "observer events",
        recorded_at: nil,
        unavailable_reason: "Storage unavailable"
      },
      {
        component: "solid_cable",
        label: "Solid Cable messages",
        available: false,
        db_size_bytes: nil,
        event_count: nil,
        record_label: "messages",
        recorded_at: nil,
        unavailable_reason: "Storage unavailable",
        trimmable_count: nil,
        oldest_message_age_seconds: nil
      }
    ])

    status, _headers, body = call_action("/solid_observer/cable?range=15m")

    expect(status).to eq(200)
    expect(body).to include("Cable overview")
    expect(body).to include("Summary in selected range")
    expect(body).to include("—")
    expect(body).not_to include("cable db unreachable")
  end

  it "renders a degraded stability strip when the backlog subquery fails" do
    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_raise(
      ActiveRecord::ConnectionNotEstablished.new("cable db unreachable")
    )

    status, _headers, body = call_action("/solid_observer/cable?range=15m")

    expect(status).to eq(200)
    expect(body).to include('data-so-zone="cable-stability"')
    expect(body).to include("Degraded")
    expect(body).not_to include("cable db unreachable")
  end

  it "renders empty states when no cable metrics or events exist" do
    status, _headers, body = call_action("/solid_observer/cable?range=15m")

    expect(status).to eq(200)
    expect(body).to include("0")
    expect(body).to include("0%")
    expect(body).to include("No chart data in the selected range yet. Summary metrics still use bounded cable stats.")
    expect(body).to include("No sampled cable events in the selected range yet. Broadcasts, rejections, and errors will appear here after Cable activity is recorded.")
  end

  it "renders eligible operational controls when the trimmable backlog is within the UI limit" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    travel_to(fixed_time) do
      seed_cable_dashboard_data(fixed_time)
      allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return(default_storage_snapshots)

      status, _headers, body = call_action("/solid_observer/cable?range=15m")

      expect(status).to eq(200)
      expect(body).to include("Operational controls")
      expect(body).to include("Trim expired messages")
      expect(body).to include("Removes expired/trimmable Solid Cable messages only. Active messages remain available to Cable.")
      expect(body).to include("Trimmable backlog: 10")
      expect(body).to include('action="/solid_observer/cable/trim"')
      expect(body).to match(/<(button|input)[^>]*class="so-btn"[^>]*(?:type="submit"|value="Trim expired messages")/)
      expect(body).not_to include("Use the Rake task")
      expect(body).not_to include("UI trim unavailable")
    end
  end

  it "renders over-limit instruction when the trimmable backlog exceeds 1,000" do
    snapshots = default_storage_snapshots
    snapshots.find { |snapshot| snapshot[:component] == "solid_cable" }[:trimmable_count] = 1001

    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return(snapshots)

    status, _headers, body = call_action("/solid_observer/cable?range=15m")

    expect(status).to eq(200)
    expect(body).to include("Operational controls")
    expect(body).to include("Use the Rake task")
    expect(body).to include("More than 1,000 expired/trimmable Solid Cable messages are pending. The UI will not run this trim. Run solid_observer:cable:trim from the server instead.")
    expect(body).to include("UI trim unavailable")
    expect(body).not_to include('action="/solid_observer/cable/trim"')
    expect(body).not_to include('<button type="submit" class="so-btn">Trim expired messages</button>')
  end

  it "renders unavailable operational controls when SolidCable::Message is not detected" do
    hide_const("SolidCable::Message")
    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return(default_storage_snapshots)

    status, _headers, body = call_action("/solid_observer/cable")

    expect(status).to eq(200)
    expect(body).to include("Operational controls")
    expect(body).to include("Cable controls are unavailable because Solid Cable support is disabled or not detected. No trim was attempted.")
    expect(body).to include("Unavailable")
    expect(body).not_to include('action="/solid_observer/cable/trim"')
    expect(body).not_to include("Trimmable backlog:")
  end
end
