# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver dashboard routes", type: :request do
  # Installs engine route helpers on the controller so that views can resolve
  # poll_data_path / live_poll_script_path in isolation (L15 / L0046).
  # When the layout is active (SCRIPT_NAME test), we also need the sidebar
  # navigation helpers that the layout calls.
  def install_path_helpers!
    controller_class = SolidObserver::DashboardController
    return if controller_class.method_defined?(:poll_data_path)

    controller_class.class_eval do
      helper_method :root_path,
        :jobs_path,
        :events_path,
        :storage_path,
        :cache_dashboard_path,
        :cache_operations_path,
        :cable_dashboard_path,
        :queue_dashboard_path,
        :poll_data_path,
        :live_poll_script_path,
        :trace_path

      def mount_prefix
        request.script_name.presence || "/solid_observer"
      end

      def root_path(...)
        mount_prefix
      end

      def jobs_path(...)
        "#{mount_prefix}/jobs"
      end

      def events_path(...)
        "#{mount_prefix}/events"
      end

      def storage_path(...)
        "#{mount_prefix}/storage"
      end

      def cache_dashboard_path(...)
        "#{mount_prefix}/cache"
      end

      def cache_operations_path(...)
        "#{mount_prefix}/cache/controls"
      end

      def cable_dashboard_path(...)
        "#{mount_prefix}/cable"
      end

      def queue_dashboard_path(...)
        "#{mount_prefix}/queue"
      end

      def poll_data_path(...)
        "#{mount_prefix}/poll_data"
      end

      def live_poll_script_path(...)
        "#{mount_prefix}/live_poll.js"
      end

      def trace_path(id)
        "#{mount_prefix}/traces/#{id}"
      end
    end
  end

  before do
    @previous_layout = SolidObserver::DashboardController.send(:_layout)
    SolidObserver::DashboardController.layout false
    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = true
    SolidObserver.config.observe_cache = false
    SolidObserver.config.storage_mode = :realtime
    SolidObserver::DashboardController.prepend_view_path(SolidObserver::Engine.root.join("app/views"))

    # Wire engine route helpers so poll_data_path/live_poll_script_path
    # resolve when rendering views in isolation (L15 / L0046).
    install_path_helpers!
  end

  after do
    SolidObserver::DashboardController.layout @previous_layout
    SolidObserver.reset_configuration!
  end

  def call_action(path)
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    status, _headers, body = SolidObserver::DashboardController.action(:index).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, response_body]
  end

  it "renders unified Home at root" do
    status, body = call_action("/solid_observer")

    expect(status).to eq(200)
    expect(body).to include("Home")
    expect(body).not_to include("Right now")
  end

  it "renders Queue overview at /queue" do
    status, body = call_action("/solid_observer/queue")

    expect(status).to eq(200)
    expect(body).to include("Right now")
  end

  it "does not reference CacheDashboardController by name" do
    controller_source = File.read(
      File.expand_path("../../../app/controllers/solid_observer/dashboard_controller.rb", __dir__)
    )
    expect(controller_source).not_to include("CacheDashboardController")
  end

  it "respects custom engine mount path via SCRIPT_NAME" do
    # Re-enable the layout for this test to verify both the src and data attributes
    SolidObserver::DashboardController.layout @previous_layout

    # Test Home at root
    env = Rack::MockRequest.env_for("/custom_observer", {
      "SCRIPT_NAME" => "/custom_observer",
      "action_dispatch.routes" => SolidObserver::Engine.routes
    })
    status, _headers, body = SolidObserver::DashboardController.action(:index).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }

    expect(status).to eq(200)
    expect(response_body).to include('src="/custom_observer/live_poll.js"')
    expect(response_body).to include("Home")

    # Test Queue at /queue still has toolbar with poll URL
    env = Rack::MockRequest.env_for("/custom_observer/queue", {
      "SCRIPT_NAME" => "/custom_observer",
      "action_dispatch.routes" => SolidObserver::Engine.routes
    })
    status, _headers, body = SolidObserver::DashboardController.action(:index).call(env)
    queue_body = +""
    body.each { |chunk| queue_body << chunk }

    expect(status).to eq(200)
    expect(queue_body).to include('data-so-poll-url="/custom_observer/poll_data"')
  ensure
    SolidObserver::DashboardController.layout false
  end
end
