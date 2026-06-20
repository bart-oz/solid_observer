# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver cable operations", type: :request do
  around do |example|
    previous_setting = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = false
    example.run
  ensure
    ActionController::Base.allow_forgery_protection = previous_setting
  end

  before do
    install_path_helpers!
    stub_const("SolidCable", Module.new)
    stub_const("SolidCable::Message", Class.new)
    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_cable = true
  end

  after { SolidObserver.reset_configuration! }

  def install_path_helpers!
    controller_class = SolidObserver::CableOperationsController
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

  def call_action(action_name, path, method: "GET")
    env = Rack::MockRequest.env_for(
      path,
      {
        "action_dispatch.routes" => SolidObserver::Engine.routes,
        "REQUEST_METHOD" => method
      }
    )

    status, headers, body = SolidObserver::CableOperationsController.action(action_name).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  it "defines the cable trim route on CableOperationsController" do
    routes_source = File.read(File.expand_path("../../../config/routes.rb", __dir__))

    expect(routes_source).to include('post "cable/trim", to: "cable_operations#trim", as: :trim_cable_operations')
  end

  it "redirects trim requests back to the cable dashboard with a notice" do
    allow(SolidObserver::Services::CableOperations).to receive(:trim).and_return(
      {ok: true, message: SolidObserver::Services::CableOperations.message(:trim, :success)}
    )

    status, headers, _body = call_action(:trim, "/solid_observer/cable/trim", method: "POST")

    expect(status).to eq(302)
    expect(headers["Location"]).to eq("http://example.org/solid_observer/cable")
  end

  it "redirects trim requests back to the cable dashboard with an alert on failure" do
    allow(SolidObserver::Services::CableOperations).to receive(:trim).and_return(
      {ok: false, message: SolidObserver::Services::CableOperations.message(:trim, :failure)}
    )

    status, headers, _body = call_action(:trim, "/solid_observer/cable/trim", method: "POST")

    expect(status).to eq(302)
    expect(headers["Location"]).to eq("http://example.org/solid_observer/cable")
  end
end
