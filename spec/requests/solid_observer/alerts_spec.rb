# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver alerts page", type: :request do
  before(:all) do
    connection = SolidObserver::BaseRecord.connection

    connection.create_table :solid_observer_alert_rules, force: true do |t|
      t.string :rule_name, null: false, limit: 120
      t.string :metric_type, null: false, limit: 50
      t.float :threshold_value, null: false
      t.string :comparison_operator, null: false, limit: 3
      t.integer :cooldown_minutes, null: false, default: 15
      t.boolean :enabled, null: false, default: true
      t.timestamps
    end
    SolidObserver::AlertRule.reset_column_information

    connection.create_table :solid_observer_alert_histories, force: true do |t|
      t.bigint :alert_rule_id, null: false
      t.datetime :triggered_at, null: false
      t.datetime :resolved_at
      t.float :metric_value, null: false
      t.string :state, null: false, limit: 16
      t.text :payload
      t.timestamps
    end
    SolidObserver::AlertHistory.reset_column_information
  end

  around do |example|
    previous_layout = SolidObserver::AlertsController.send(:_layout)
    SolidObserver::AlertsController.layout false
    example.run
  ensure
    SolidObserver::AlertsController.layout previous_layout
  end

  before do
    ensure_engine_view_path!
    install_path_helpers!

    SolidObserver.config.ui_enabled = true
    SolidObserver.config.alerts_enabled = true
    SolidObserver.config.storage_mode = :persistence

    SolidObserver::AlertHistory.delete_all
    SolidObserver::AlertRule.delete_all
  end

  after { SolidObserver.reset_configuration! }

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(SolidObserver::AlertsController.superclass).to eq(SolidObserver::ApplicationController)
    end

    it "registers :require_persistence_mode as a before_action" do
      callbacks = SolidObserver::AlertsController._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_persistence_mode)
    end
  end

  describe "GET /alerts" do
    it "renders successfully with no data" do
      status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(status).to eq(200)
      expect(body).to include("No alert rules are defined")
      expect(body).to include("No alerts are currently firing")
    end

    it "lists rule configuration" do
      create_rule

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).to include("queue backlog")
      expect(body).to include("Queue latency")
      expect(body).to include("&gt; 100.0")
      expect(body).to include("15 minutes")
    end

    it "marks disabled rules" do
      create_rule(enabled: false)

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).to include(">disabled<")
    end

    it "shows firing incidents with their severity and value" do
      create_history(create_rule)

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).to include(">triggered<")
      expect(body).to include("critical")
      expect(body).to include("250.0")
    end

    it "keeps resolved incidents out of the active section" do
      create_history(create_rule, state: "resolved")

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).to include("No alerts are currently firing")
      expect(body).to include(">resolved<")
    end

    it "renders no payload field outside the safe allowlist" do
      create_history(create_rule, payload: {"job_arguments" => "SECRET-ARG", "metadata" => "SECRET-META"})

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).not_to include("SECRET-ARG")
      expect(body).not_to include("SECRET-META")
    end

    it "renders no configured notification credential" do
      SolidObserver.config.slack_webhook_url = "https://hooks.example.com/SECRET-HOOK"
      SolidObserver.config.webhook_secret = "SECRET-SIGNING-KEY"
      create_history(create_rule)

      _status, _headers, body = call_action("/solid_observer/alerts", action: :index)

      expect(body).not_to include("SECRET-HOOK")
      expect(body).not_to include("SECRET-SIGNING-KEY")
    end

    it "redirects to the dashboard in realtime mode" do
      SolidObserver.config.storage_mode = :realtime

      status, headers, _body = call_action("/solid_observer/alerts", action: :index)

      expect(status).to eq(302)
      expect(headers["Location"]).to end_with("/solid_observer")
      expect(flash_hash[:alert]).to eq("This page is not available in real-time mode.")
    end

    it "does not query the alert tables in realtime mode" do
      SolidObserver.config.storage_mode = :realtime
      allow(SolidObserver::AlertRule).to receive(:order)

      call_action("/solid_observer/alerts", action: :index)

      expect(SolidObserver::AlertRule).not_to have_received(:order)
    end
  end

  describe "GET /alerts/:id" do
    it "renders the rule and its history" do
      rule = create_rule
      create_history(rule)

      status, _headers, body = call_action("/solid_observer/alerts/#{rule.id}", action: :show, id: rule.id.to_s)

      expect(status).to eq(200)
      expect(body).to include("queue backlog")
      expect(body).to include("Recent history")
      expect(body).to include(">triggered<")
    end

    it "reports an empty state for a rule that never fired" do
      rule = create_rule

      _status, _headers, body = call_action("/solid_observer/alerts/#{rule.id}", action: :show, id: rule.id.to_s)

      expect(body).to include("This rule has not fired yet")
    end

    it "redirects with a flash alert when the rule does not exist" do
      status, headers, _body = call_action("/solid_observer/alerts/999999", action: :show, id: "999999")

      expect(status).to eq(302)
      expect(headers["Location"]).to end_with("/solid_observer/alerts")
      expect(flash_hash[:alert]).to eq("Alert rule not found")
    end
  end

  def create_rule(rule_name: "queue backlog", enabled: true)
    SolidObserver::AlertRule.create!(
      rule_name: rule_name,
      metric_type: "queue_latency",
      comparison_operator: ">",
      threshold_value: 100.0,
      cooldown_minutes: 15,
      enabled: enabled
    )
  end

  def create_history(rule, state: "triggered", payload: {})
    SolidObserver::AlertHistory.create!(
      alert_rule: rule,
      state: state,
      metric_value: 250.0,
      triggered_at: Time.current,
      resolved_at: (state == "resolved") ? Time.current : nil,
      payload: {"rule_name" => rule.rule_name, "severity" => "critical"}.merge(payload).to_json
    )
  end

  def ensure_engine_view_path!
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    return if SolidObserver::AlertsController.view_paths.map(&:to_s).include?(engine_views)

    SolidObserver::AlertsController.prepend_view_path(engine_views)
  end

  # Guarded by an own sentinel, never by `method_defined?(:alerts_path)`: once any
  # other spec draws the engine routes, the real url_helpers already define that
  # method, the installer would bail out, and the real `root_path` would run
  # without a request (L0097 — suite order silently changes behaviour).
  def install_path_helpers!
    controller_class = SolidObserver::AlertsController
    return if controller_class.instance_variable_get(:@so_spec_path_helpers)

    controller_class.instance_variable_set(:@so_spec_path_helpers, true)

    controller_class.class_eval do
      helper_method :root_path, :alerts_path, :alert_path

      def root_path
        "/solid_observer"
      end

      def alerts_path
        "/solid_observer/alerts"
      end

      def alert_path(rule)
        "/solid_observer/alerts/#{rule.respond_to?(:to_param) ? rule.to_param : rule}"
      end
    end
  end

  # No Flash middleware in this bare Rack env, so hand the request the hash the
  # middleware would normally install; `redirect_to ..., alert:` writes into it.
  def flash_hash
    @flash_hash ||= ActionDispatch::Flash::FlashHash.new
  end

  def call_action(path, action:, id: nil)
    env = Rack::MockRequest.env_for(path, {"action_dispatch.routes" => SolidObserver::Engine.routes})
    env["action_dispatch.request.flash_hash"] = flash_hash
    env["action_dispatch.request.path_parameters"] = {controller: "solid_observer/alerts", action: action.to_s, id: id} if id
    status, headers, body = SolidObserver::AlertsController.action(action).call(env)
    response_body = +""
    body.each { |chunk| response_body << chunk }
    [status, headers, response_body]
  end
end
