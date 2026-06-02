# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver cache dashboard", type: :request do
  before(:all) do
    connection = SolidObserver::CacheMetric.connection

    next if connection.table_exists?(:solid_observer_cache_metrics)

    connection.create_table :solid_observer_cache_metrics do |t|
      t.string :event_type, null: false, limit: 64
      t.datetime :period_start, null: false
      t.bigint :operations_count, null: false, default: 0
      t.bigint :hits_count, null: false, default: 0
      t.bigint :misses_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
      t.float :duration_total, null: false, default: 0.0
    end
  end

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

  before do
    ensure_engine_view_path!
    install_path_helpers!

    stub_const("SolidCache", Module.new)
    stub_const("SolidCache::Record", Class.new(ActiveRecord::Base) do
      self.table_name = "solid_cache_entries"
    end)

    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = false
    SolidObserver.config.observe_cache = true
    SolidObserver.config.storage_mode = :persistence

    SolidObserver::CacheMetric.delete_all
    SolidObserver::CacheEvent.delete_all
    SolidCache::Record.delete_all
  end

  after { SolidObserver.reset_configuration! }

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    current_paths = SolidObserver::CacheDashboardController.view_paths.map(&:to_s)
    return if current_paths.include?(engine_views)

    SolidObserver::CacheDashboardController.prepend_view_path(engine_views)
  end

  def install_path_helpers!
    controller_class = SolidObserver::CacheDashboardController
    return if controller_class.method_defined?(:cache_dashboard_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :storage_path,
        :cache_dashboard_path,
        :cache_operations_path,
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

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end
    end
  end

  def call_action(path)
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    status, headers, body = SolidObserver::CacheDashboardController.action(:index).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  it "defines the cache overview route on CacheDashboardController" do
    routes_source = File.read(File.expand_path("../../../config/routes.rb", __dir__))

    expect(routes_source).to include('get "cache", to: "cache_dashboard#index", as: :cache_dashboard')
  end

  it "renders the cache overview with bounded summary data, chart empty state, and sampled events" do
    fixed_time = Time.utc(2026, 6, 2, 12, 0, 0)

    travel_to(fixed_time) do
      SolidObserver::CacheMetric.create!(
        event_type: "cache_read",
        period_start: fixed_time.beginning_of_minute,
        operations_count: 40,
        hits_count: 30,
        misses_count: 10,
        errors_count: 4,
        duration_total: 5.2
      )
      SolidObserver::CacheMetric.create!(
        event_type: "cache_read",
        period_start: 2.hours.ago.beginning_of_minute,
        operations_count: 500,
        hits_count: 400,
        misses_count: 100,
        errors_count: 0,
        duration_total: 50.0
      )

      SolidObserver::CacheEvent.create!(
        event_type: "cache_read",
        key_digest: "abcdef1234567890",
        hit: true,
        duration: 0.003,
        metadata: "{}",
        recorded_at: 5.minutes.ago
      )
      SolidObserver::CacheEvent.create!(
        event_type: "cache_write",
        key_digest: "fedcba0987654321",
        hit: nil,
        duration: 1.2,
        error_class: "RuntimeError",
        error_message: "adapter internals should stay hidden",
        metadata: "{}",
        recorded_at: 3.minutes.ago
      )
      SolidObserver::CacheEvent.create!(
        event_type: "cache_fetch",
        key_digest: "1122334455667788",
        hit: nil,
        duration: nil,
        metadata: "{}",
        recorded_at: 2.minutes.ago
      )
      SolidObserver::CacheEvent.create!(
        event_type: "cache_delete",
        key_digest: "olddigest00000000",
        hit: false,
        duration: 0.001,
        metadata: "{}",
        recorded_at: 2.hours.ago
      )
      SolidCache::Record.create!(key: "cache-key", value: "cached")

      status, _headers, body = call_action("/solid_observer/cache?range=15m")

      expect(status).to eq(200)
      expect(body).to include("Cache overview")
      expect(body).to include("Available")
      expect(body).to include("Selected range: in last 15m · keys and values are never shown.")
      expect(body).to include("Apply range")
      expect(body).to include("Summary in selected range")
      expect(body).to include("75%")
      expect(body).to include("40")
      expect(body).to include("10%")
      expect(body).to include("130ms")
      expect(body).to include("SolidCache + cache observer")
      expect(body).to include("Activity trends")
      expect(body).to include("No chart data in the selected range yet. Summary metrics still use bounded cache stats.")
      expect(body).to include("Sampled recent events")
      expect(body).to include("debug context only · no raw keys or values")
      expect(body).to include("abcdef1234…")
      expect(body).to include("fedcba0987…")
      expect(body).to include("1122334455…")
      expect(body).to include("Hit")
      expect(body).to include("Error")
      expect(body).to include("so-badge--recorded")
      expect(body).not_to include("olddigest0000")
      expect(body).not_to include("adapter internals should stay hidden")
      expect(body).not_to include("cache-key")
    end
  end

  it "renders a guarded unavailable state and hides cache navigation when cache support is disabled" do
    SolidObserver.config.observe_cache = false

    status, _headers, body = call_action("/solid_observer/cache")

    expect(status).to eq(200)
    expect(body).to include("Cache dashboard unavailable")
    expect(body).to include("Unavailable")
    expect(body).to include("Cache dashboard is unavailable because SolidCache support is disabled or not detected. Metrics are unavailable.")
    expect(body).not_to include("Apply range")
    expect(body).not_to include("Summary in selected range")
    expect(body).not_to include("Sampled recent events")
    expect(body).not_to include('href="/solid_observer/cache"')
  end

  it "falls back to an empty recent-events state when sampled event queries fail" do
    allow(SolidObserver::CacheEvent).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("missing table"))

    status, _headers, body = call_action("/solid_observer/cache?range=15m")

    expect(status).to eq(200)
    expect(body).to include("No sampled cache events in the selected range yet. Slow, sampled, or errored cache operations will appear here.")
    expect(body).not_to include("missing table")
  end
end
