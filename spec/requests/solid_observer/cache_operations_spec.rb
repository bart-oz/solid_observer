# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver cache operations", type: :request do
  let(:store_class) do
    Class.new do
      attr_reader :expiry_batch_size, :max_age, :max_entries, :max_size

      def initialize
        @expiry_batch_size = 12
        @max_age = 300
        @max_entries = 20
        @max_size = 2048
      end

      def clear(_options = nil)
      end

      def cleanup(_options = nil)
      end

      def with_each_connection
        yield
      end
    end
  end
  let(:cache_store) { store_class.new }

  around do |example|
    previous_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous_setting
  end

  before do
    ensure_engine_view_path!
    install_path_helpers!
    stub_const("SolidCache", Module.new)
    stub_const("SolidCache::Store", store_class)
    allow(Rails).to receive(:cache).and_return(cache_store)
    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_cache = true
  end

  after { SolidObserver.reset_configuration! }

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    current_paths = SolidObserver::CacheOperationsController.view_paths.map(&:to_s)
    return if current_paths.include?(engine_views)

    SolidObserver::CacheOperationsController.prepend_view_path(engine_views)
  end

  def build_flash(messages)
    ActionDispatch::Flash::FlashHash.new.tap do |flash_hash|
      messages.each { |key, value| flash_hash[key] = value }
    end
  end

  def install_path_helpers!
    controller_class = SolidObserver::CacheOperationsController
    return if controller_class.method_defined?(:cache_operations_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :storage_path,
        :cache_dashboard_path,
        :cache_operations_path,
        :prune_cache_operations_path,
        :clear_cache_operations_path,
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

      def prune_cache_operations_path
        "/solid_observer/cache/controls/prune"
      end

      def clear_cache_operations_path
        "/solid_observer/cache/controls/clear"
      end

      def live_poll_script_path
        "/solid_observer/live_poll.js"
      end
    end
  end

  def call_action(action_name, path, method: "GET", flash: {})
    env = Rack::MockRequest.env_for(
      path,
      {
        "action_dispatch.routes" => SolidObserver::Engine.routes,
        "REQUEST_METHOD" => method,
        "action_dispatch.request.flash_hash" => build_flash(flash)
      }
    )

    status, headers, body = SolidObserver::CacheOperationsController.action(action_name).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  it "defines cache controls routes" do
    routes_source = File.read(File.expand_path("../../../config/routes.rb", __dir__))

    expect(routes_source).to include('get "cache/controls", to: "cache_operations#index", as: :cache_operations')
    expect(routes_source).to include('post "cache/controls/prune", to: "cache_operations#prune", as: :prune_cache_operations')
    expect(routes_source).to include('post "cache/controls/clear", to: "cache_operations#clear", as: :clear_cache_operations')
  end

  it "renders the controls-only UI when cache operations are available" do
    status, _headers, body = call_action(:index, "/solid_observer/cache/controls")

    expect(status).to eq(200)
    expect(body).to include("Cache controls")
    expect(body).to include("Operational controls")
    expect(body).to include("Prune expired entries")
    expect(body).to include("Clear cache")
    expect(body).to include("Available")
    expect(body).to include('href="/solid_observer/cache/controls"')
    expect(body).to include('action="/solid_observer/cache/controls/prune"')
    expect(body).to include('action="/solid_observer/cache/controls/clear"')
    expect(body).to include(SolidObserver::Services::CacheOperations.message(:clear, :confirmation))
    expect(body).not_to include(SolidObserver::Services::CacheOperations.unavailable_message)
  end

  it "renders a single unavailable state when cache controls are disabled" do
    SolidObserver.config.observe_cache = false

    status, _headers, body = call_action(:index, "/solid_observer/cache/controls")

    expect(status).to eq(200)
    expect(body).to include("Cache controls")
    expect(body).to include("Unavailable")
    expect(body).to include(SolidObserver::Services::CacheOperations.unavailable_message)
    expect(body).not_to include('href="/solid_observer/cache/controls"')
    expect(body).not_to include('action="/solid_observer/cache/controls/prune"')
    expect(body).not_to include('action="/solid_observer/cache/controls/clear"')
  end

  it "renders accessible flash announcement roles" do
    status, _headers, body = call_action(
      :index,
      "/solid_observer/cache/controls",
      flash: {
        notice: SolidObserver::Services::CacheOperations.message(:clear, :success),
        alert: SolidObserver::Services::CacheOperations.message(:prune, :failure)
      }
    )

    expect(status).to eq(200)
    expect(body).to include('role="status"')
    expect(body).to include('aria-live="polite"')
    expect(body).to include('role="alert"')
  end

  it "redirects prune requests back to the controls page" do
    allow(SolidObserver::Services::CacheOperations).to receive(:prune).and_return(
      {ok: true, message: SolidObserver::Services::CacheOperations.message(:prune, :success)}
    )

    status, headers, _body = call_action(:prune, "/solid_observer/cache/controls/prune", method: "POST")

    expect(status).to eq(302)
    expect(headers["Location"]).to eq("http://example.org/solid_observer/cache/controls")
  end
end
