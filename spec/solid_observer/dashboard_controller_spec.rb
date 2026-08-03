# frozen_string_literal: true

require "spec_helper"
require "base64"
require_relative "../../app/helpers/solid_observer/application_helper"

RSpec.describe SolidObserver::DashboardController do
  after do
    SolidObserver::ChartBuffer.clear
    SolidObserver.reset_configuration!
  end

  let(:controller) { described_class.allocate }

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    current_paths = described_class.view_paths.map(&:to_s)
    return if current_paths.include?(engine_views)

    described_class.prepend_view_path(engine_views)
  end

  def call_controller_action(action_name, path = "/", env_overrides = {})
    ensure_engine_view_path!
    described_class.helper(SolidObserver::ApplicationHelper)
    env = Rack::MockRequest.env_for(
      path,
      {"action_dispatch.routes" => SolidObserver::Engine.routes}.merge(env_overrides)
    )
    status, headers, body = described_class.action(action_name).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end

    it "does not reference CacheDashboardController by name" do
      controller_source = File.read(
        File.expand_path("../../app/controllers/solid_observer/dashboard_controller.rb", __dir__)
      )
      expect(controller_source).not_to include("CacheDashboardController")
    end
  end

  describe "#index" do
    let(:params_hash) { {} }
    let(:stats) do
      {
        ready: 3,
        scheduled: 1,
        claimed: 0,
        failed: 2,
        workers: 1,
        queues: {},
        available: true,
        range: "15m"
      }
    end
    let(:component_params) { {component: "queue"} }
    let(:component_path) { "/solid_observer/queue" }
    let(:request_double) do
      instance_double(
        ActionDispatch::Request,
        query_parameters: params_hash.transform_keys(&:to_s),
        path_parameters: component_params,
        path: component_path
      )
    end

    before do
      allow(controller).to receive(:request).and_return(request_double)
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
      allow(SolidObserver::QueueStats).to receive(:chart_data).and_return(
        {performed: [], failed: [], ready: []}
      )
    end

    it "assigns @stats from QueueStats.snapshot and exposes available ranges" do
      SolidObserver.config.storage_mode = :realtime
      controller.index

      expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
      expect(controller.instance_variable_get(:@stats)).to eq(stats)
      expect(controller.instance_variable_get(:@range)).to eq("15m")
    end

    it "assigns @chart from QueueStats.chart_data with performed, failed, and ready keys" do
      chart_data = {
        performed: [{t: 100, v: 5}, {t: 200, v: 10}],
        failed: [{t: 100, v: 1}],
        ready: [{t: 100, v: 3}, {t: 200, v: 7}]
      }
      allow(SolidObserver::QueueStats).to receive(:chart_data).and_return(chart_data)
      allow(SolidObserver::QueueEvent).to receive(:recent).with(10).and_return([])
      SolidObserver.config.storage_mode = :persistence
      controller.index

      expect(SolidObserver::QueueStats).to have_received(:chart_data).with(window: 15.minutes)
      result = controller.instance_variable_get(:@chart)
      expect(result).to include(:performed, :failed, :ready)
    end

    describe "GET #index with range param" do
      context "with a valid range" do
        let(:params_hash) { {range: "15m"} }
        let(:stats) { super().merge(range: "15m") }

        it "uses the provided range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
          expect(controller.instance_variable_get(:@range)).to eq("15m")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("15m")
        end
      end

      context "with an invalid range" do
        let(:params_hash) { {range: "999d"} }

        it "falls back to the default range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
          expect(controller.instance_variable_get(:@range)).to eq("15m")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("15m")
        end
      end

      context "with no range" do
        it "falls back to the default range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
          expect(controller.instance_variable_get(:@range)).to eq("15m")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("15m")
        end
      end
    end

    describe "GET #index with live param" do
      before { SolidObserver.config.storage_mode = :realtime }

      context "when live=on" do
        let(:params_hash) { {live: "on"} }

        it "assigns @live as true" do
          controller.index

          expect(controller.instance_variable_get(:@live)).to be(true)
        end
      end

      context "when live=off" do
        let(:params_hash) { {live: "off"} }

        it "assigns @live as false" do
          controller.index

          expect(controller.instance_variable_get(:@live)).to be(false)
        end
      end

      context "when live is missing" do
        let(:params_hash) { {} }

        it "assigns @live as false" do
          controller.index

          expect(controller.instance_variable_get(:@live)).to be(false)
        end
      end

      context "when live has a garbage value" do
        let(:params_hash) { {live: "blah"} }

        it "assigns @live as false" do
          controller.index

          expect(controller.instance_variable_get(:@live)).to be(false)
        end
      end

      context "when range and live coexist" do
        let(:params_hash) { {range: "15m", live: "on"} }
        let(:stats) { super().merge(range: "15m") }

        it "assigns both @range and @live from params" do
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
          expect(controller.instance_variable_get(:@range)).to eq("15m")
          expect(controller.instance_variable_get(:@live)).to be(true)
        end
      end
    end

    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      let(:events_scope) { double("events_scope") }
      let(:stats) do
        super().merge(
          performed_in_range: 22,
          failed_in_range: 4,
          enqueue_rate_per_min: 1.8
        )
      end

      before do
        allow(SolidObserver::QueueEvent).to receive(:recent).with(10).and_return(events_scope)
      end

      it "assigns persistence-only data and scoped stats" do
        controller.index

        expect(controller.instance_variable_get(:@recent_events)).to eq(events_scope)
        expect(controller.instance_variable_get(:@stats)).to include(
          :performed_in_range,
          :failed_in_range,
          :enqueue_rate_per_min
        )
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      let(:stats) { super().except(:performed_in_range, :failed_in_range, :enqueue_rate_per_min) }

      it "does not assign persistence-only data or scoped keys" do
        controller.index

        expect(controller.instance_variable_get(:@recent_events)).to be_nil
        expect(controller.instance_variable_get(:@stats)).not_to include(
          :performed_in_range,
          :failed_in_range,
          :enqueue_rate_per_min
        )
      end
    end

    context "for home component" do
      let(:component_params) { {} }
      let(:component_path) { "/" }

      before do
        allow(SolidObserver::Services::HealthScore).to receive(:call).and_return({overall: :ok, components: {}})
        allow(SolidObserver::Services::UnifiedFeed).to receive(:call).and_return([])
      end

      it "assigns @component as home and loads health and feed" do
        controller.index

        expect(controller.instance_variable_get(:@component)).to eq("home")
        expect(controller.instance_variable_get(:@health)).to eq({overall: :ok, components: {}})
        expect(controller.instance_variable_get(:@feed)).to eq([])
      end

      it "falls back to degraded health when HealthScore raises but still loads feed" do
        allow(SolidObserver::Services::HealthScore).to receive(:call).and_raise(StandardError)
        feed_items = [{component: "queue", event_type: "job_completed"}]
        allow(SolidObserver::Services::UnifiedFeed).to receive(:call).and_return(feed_items)

        controller.index

        expect(controller.instance_variable_get(:@health)).to eq({overall: :degraded, components: {}})
        expect(controller.instance_variable_get(:@feed)).to eq(feed_items)
      end

      it "falls back to empty feed when UnifiedFeed raises but still has health" do
        health = {overall: :ok, components: {queue: :stable}}
        allow(SolidObserver::Services::HealthScore).to receive(:call).and_return(health)
        allow(SolidObserver::Services::UnifiedFeed).to receive(:call).and_raise(StandardError)

        controller.index

        expect(controller.instance_variable_get(:@health)).to eq(health)
        expect(controller.instance_variable_get(:@feed)).to eq([])
      end

      it "does not call QueueStats.snapshot" do
        controller.index

        expect(SolidObserver::QueueStats).not_to have_received(:snapshot)
      end
    end
  end

  describe "#live_poll" do
    def basic_auth_header(username, password)
      token = Base64.strict_encode64("#{username}:#{password}")
      "Basic #{token}"
    end

    it "sets HTTP caching headers" do
      status, headers, _body = call_controller_action(
        :live_poll,
        "/solid_observer/live_poll.js",
        {"HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"}
      )

      expect(status).to eq(200)
      expect(headers["Cache-Control"]).to include("public")
      expect(headers["Cache-Control"]).to include("max-age")
    end

    it "returns javascript without layout chrome" do
      status, headers, body = call_controller_action(
        :live_poll,
        "/solid_observer/live_poll.js",
        {"HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"}
      )

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to include("application/javascript")
      expect(body).to include("function init()")
      expect(body).not_to include("<html")
      expect(body).not_to include("so-sidebar")
    end

    it "returns 404 when ui is disabled" do
      SolidObserver.config.ui_enabled = false

      status, _headers, body = call_controller_action(:live_poll, "/solid_observer/live_poll.js")

      expect(status).to eq(404)
      expect(body).to include("Not Found")
    end

    context "with HTTP basic auth configured" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = "secret"
      end

      it "requires authentication" do
        status, headers, _body = call_controller_action(:live_poll, "/solid_observer/live_poll.js")

        expect(status).to eq(401)
        expect(headers["WWW-Authenticate"]).to include("Basic realm=\"SolidObserver\"")
      end

      it "returns javascript when credentials are valid" do
        status, headers, body = call_controller_action(
          :live_poll,
          "/solid_observer/live_poll.js",
          {
            "HTTP_AUTHORIZATION" => basic_auth_header("admin", "secret"),
            "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest"
          }
        )

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to include("application/javascript")
        expect(body).to include("window.history.replaceState")
      end
    end
  end

  describe "#poll_data" do
    def basic_auth_header(username, password)
      token = Base64.strict_encode64("#{username}:#{password}")
      "Basic #{token}"
    end

    def parse_json(body)
      JSON.parse(body).deep_symbolize_keys
    end

    before do
      stub_const("SolidQueue", Module.new)
      stub_const("SolidQueue::Job", Class.new)
      stub_const("SolidQueue::ReadyExecution", Class.new do
        def self.count
          0
        end
      end)
      allow(SolidQueue::ReadyExecution).to receive(:count).and_return(3)
      allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true)
    end

    it "returns 200 json payload with locked key shape" do
      SolidObserver.config.storage_mode = :persistence
      allow(SolidObserver::QueueStats).to receive(:snapshot_for_poll).with(range: "15m").and_return(
        {
          ready: 3,
          scheduled: 1,
          claimed: 0,
          workers: 1,
          failed: 2,
          enqueue_rate_per_min: 1.2,
          performed_in_range: 34,
          failed_in_range: 2,
          enqueued_in_range: 40,
          avg_duration_in_range: 1.2,
          queues: {"default" => 3},
          performed_by_queue: {"default" => 30},
          failed_by_queue: {"default" => 2}
        }
      )
      allow(SolidObserver::QueueStats).to receive(:chart_data).with(window: 15.minutes).and_return(
        {
          performed: [{t: 1, v: 2}],
          failed: [{t: 1, v: 1}],
          ready: [{t: 1, v: 3}]
        }
      )

      status, headers, body = call_controller_action(:poll_data, "/solid_observer/poll_data?range=15m")
      payload = parse_json(body)

      expect(status).to eq(200)
      expect(headers["Content-Type"]).to include("application/json")
      expect(payload.keys.sort).to eq(%i[chart mode range_label snapshot])
      expect(payload[:mode]).to eq("persistence")
      expect(payload[:range_label]).to eq("in last 15m")
      expect(payload[:snapshot]).to include(:ready, :scheduled, :claimed, :workers, :failed, :enqueue_rate_per_min, :performed_in_range, :failed_in_range, :enqueued_in_range, :avg_duration_in_range, :queues, :performed_by_queue, :failed_by_queue)
      expect(payload[:chart].keys.sort).to eq(%i[failed performed ready])
    end

    it "falls back unknown range to 15m" do
      allow(SolidObserver::QueueStats).to receive(:snapshot_for_poll).with(range: "15m").and_return(
        {
          ready: 0,
          scheduled: 0,
          claimed: 0,
          workers: 0,
          failed: 0,
          enqueue_rate_per_min: nil
        }
      )
      allow(SolidObserver::QueueStats).to receive(:chart_data).with(window: 15.minutes).and_return(
        {
          performed: [],
          failed: [],
          ready: []
        }
      )

      status, _headers, _body = call_controller_action(:poll_data, "/solid_observer/poll_data?range=unknown")

      expect(status).to eq(200)
    end

    it "uses realtime response semantics and does not query QueueEvent throughput" do
      SolidObserver.config.storage_mode = :realtime
      allow(SolidObserver::QueueStats).to receive(:snapshot_for_poll).and_call_original
      allow(SolidObserver::QueueStats).to receive(:chart_data).and_call_original
      expect(SolidObserver::QueueEvent).not_to receive(:count_by_time_bucket)
      expect(SolidObserver::QueueEvent).not_to receive(:enqueue_rate_per_minute)

      status, _headers, body = call_controller_action(:poll_data, "/solid_observer/poll_data?range=15m")
      payload = parse_json(body)

      expect(status).to eq(200)
      expect(payload[:mode]).to eq("realtime")
      expect(payload[:chart][:performed]).to eq([])
      expect(payload[:chart][:failed]).to eq([])
      expect(payload[:chart][:ready]).to be_a(Array)
      expect(payload[:snapshot][:enqueue_rate_per_min]).to be_nil
    end

    it "appends to ChartBuffer and deduplicates samples in the same second" do
      SolidObserver.config.storage_mode = :realtime
      fixed_time = Time.utc(2026, 5, 10, 13, 0, 0)

      travel_to(fixed_time) do
        call_controller_action(:poll_data, "/solid_observer/poll_data?range=15m")
        call_controller_action(:poll_data, "/solid_observer/poll_data?range=15m")
      end

      samples = SolidObserver::ChartBuffer.recent(10.years.to_i)
      expect(samples.count).to eq(1)
      expect(samples.first).to eq({t: fixed_time.to_i, v: 3})
    end

    it "returns 404 when ui is disabled" do
      SolidObserver.config.ui_enabled = false

      status, _headers, body = call_controller_action(:poll_data, "/solid_observer/poll_data")

      expect(status).to eq(404)
      expect(body).to include("Not Found")
    end

    it "returns lightweight tick payload with chart nil when tick=true" do
      SolidObserver.config.storage_mode = :persistence
      allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true)

      tick_snapshot = {
        ready: 5,
        scheduled: 1,
        claimed: 2,
        workers: 3,
        failed: 0
      }
      allow(SolidObserver::QueueStats).to receive(:snapshot_for_tick).and_return(tick_snapshot)

      status, _, body = call_controller_action(:poll_data, "/solid_observer/poll_data?range=15m&tick=true")
      payload = parse_json(body)

      expect(status).to eq(200)
      expect(payload[:mode]).to eq("persistence")
      expect(payload[:snapshot]).to include(:ready, :scheduled, :claimed, :workers, :failed)
      expect(payload[:snapshot]).not_to include(:performed_in_range, :failed_in_range, :enqueued_in_range, :avg_duration_in_range, :queues, :performed_by_queue, :failed_by_queue)
      expect(payload[:chart]).to be_nil
    end

    context "with HTTP basic auth configured" do
      before do
        SolidObserver.config.ui_enabled = true
        SolidObserver.config.ui_username = "admin"
        SolidObserver.config.ui_password = "secret"
      end

      it "requires authentication" do
        status, headers, _body = call_controller_action(:poll_data, "/solid_observer/poll_data")

        expect(status).to eq(401)
        expect(headers["WWW-Authenticate"]).to include("Basic realm=\"SolidObserver\"")
      end

      it "returns json when credentials are valid" do
        allow(SolidObserver::QueueStats).to receive(:snapshot_for_poll).and_return(
          {
            ready: 0,
            scheduled: 0,
            claimed: 0,
            workers: 0,
            failed: 0,
            enqueue_rate_per_min: nil
          }
        )
        allow(SolidObserver::QueueStats).to receive(:chart_data).and_return(
          {
            performed: [],
            failed: [],
            ready: []
          }
        )

        status, headers, _body = call_controller_action(
          :poll_data,
          "/solid_observer/poll_data",
          {"HTTP_AUTHORIZATION" => basic_auth_header("admin", "secret")}
        )

        expect(status).to eq(200)
        expect(headers["Content-Type"]).to include("application/json")
      end
    end
  end
end
