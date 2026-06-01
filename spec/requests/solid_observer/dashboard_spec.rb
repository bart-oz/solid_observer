# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver dashboard routes", type: :request do
  before do
    @previous_layout = SolidObserver::DashboardController.send(:_layout)
    SolidObserver::DashboardController.layout false
    SolidObserver.config.ui_enabled = true
    SolidObserver.config.observe_queue = true
    SolidObserver.config.observe_cache = false
    SolidObserver.config.storage_mode = :realtime
    SolidObserver::DashboardController.prepend_view_path(SolidObserver::Engine.root.join("app/views"))
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

  it "keeps the existing queue dashboard path" do
    status, body = call_action("/solid_observer")

    expect(status).to eq(200)
    expect(body).to include("Right now")
  end

  it "supports explicit queue dashboard routing" do
    status, body = call_action("/solid_observer/queue")

    expect(status).to eq(200)
    expect(body).to include("Right now")
  end

  it "supports cache dashboard route when cache component is enabled" do
    stub_const("SolidCache", Module.new)
    SolidObserver.config.observe_cache = true

    status, body = call_action("/solid_observer/cache")

    expect(status).to eq(200)
    expect(body).to include("Dashboard")
  end
end
