# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Alerts do
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

  subject(:cli) { described_class.new }

  before do
    SolidObserver::AlertHistory.delete_all
    SolidObserver::AlertRule.delete_all
    allow(SolidObserver.config).to receive(:realtime_mode?).and_return(false)
    allow(SolidObserver.config).to receive(:alerts_enabled).and_return(true)
  end

  after { SolidObserver.reset_configuration! }

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

  describe "#list" do
    it "prints the header" do
      expect { cli.list }.to output(/🔔 SolidObserver Alerts/).to_stdout
    end

    it "prints each rule with metric, threshold, cooldown, and state" do
      create_rule

      output = capture_stdout { cli.list }

      expect(output).to match(/queue backlog\s+queue_latency\s+> 100\.0\s+15m\s+enabled/)
    end

    it "distinguishes disabled rules" do
      create_rule(rule_name: "muted rule", enabled: false)

      expect(capture_stdout { cli.list }).to match(/muted rule.+disabled/)
    end

    it "reports an empty state instead of a rules table when none are defined" do
      output = capture_stdout { cli.list }

      expect(output).to include("No alert rules defined")
      expect(output).not_to include("Threshold")
    end

    it "lists active incidents" do
      create_history(create_rule)

      output = capture_stdout { cli.list }

      expect(output).to match(/Active incidents/)
      expect(output).to match(/queue backlog\s+triggered\s+critical\s+250\.0/)
    end

    it "reports an empty state when nothing is firing" do
      create_history(create_rule, state: "resolved")

      expect(capture_stdout { cli.list }).to match(/Active incidents\n\s*None/)
    end

    it "includes resolved rows in recent history" do
      create_history(create_rule, state: "resolved")

      expect(capture_stdout { cli.list }).to match(/Recent history/)
    end

    it "honours the limit argument" do
      rule = create_rule
      3.times { |i| create_history(rule, state: "resolved", payload: {"severity" => "sev#{i}"}) }

      output = capture_stdout { cli.list(limit: 1) }

      expect(output.scan(/sev\d/).size).to eq(1)
    end

    it "falls back to the default limit for junk input" do
      rule = create_rule
      2.times { |i| create_history(rule, state: "resolved", payload: {"severity" => "sev#{i}"}) }

      expect(capture_stdout { cli.list(limit: "not-a-number") }.scan(/sev\d/).size).to eq(2)
    end

    it "skips without querying when alerts are disabled" do
      allow(SolidObserver.config).to receive(:alerts_enabled).and_return(false)

      expect(capture_stdout { cli.list }).to include("Alerting is unavailable")
    end

    it "skips in realtime mode" do
      allow(SolidObserver.config).to receive(:realtime_mode?).and_return(true)

      expect(capture_stdout { cli.list }).to include("Alerting is unavailable")
    end

    it "never prints raw payload fields outside the safe allowlist" do
      rule = create_rule
      create_history(rule, payload: {"job_arguments" => "SECRET-ARG"})

      expect(capture_stdout { cli.list }).not_to include("SECRET-ARG")
    end

    # AC3: the CLI deliberately has no rescue. A future defensive `rescue` here
    # would turn an operator diagnostic into a silent exit-0 warning.
    it "lets storage errors propagate instead of degrading" do
      allow(SolidObserver::AlertRule).to receive(:order)
        .and_raise(ActiveRecord::StatementInvalid.new("no such table"))

      expect { capture_stdout { cli.list } }.to raise_error(ActiveRecord::StatementInvalid)
    end
  end

  describe "#test" do
    let(:success) do
      SolidObserver::Services::AlertNotification::DeliveryResult.new(
        channel: :slack, status: :success, attempted_at: Time.current
      )
    end

    let(:failure) do
      SolidObserver::Services::AlertNotification::DeliveryResult.new(
        channel: :webhook, status: :failed, error_class: "Net::OpenTimeout",
        error_message: "https://hooks.example.com/SECRET-TOKEN timed out", attempted_at: Time.current
      )
    end

    def stub_notification(results)
      allow(SolidObserver::Services::AlertNotification).to receive(:call).and_return(results)
    end

    # Captures stdout and the boolean the rake wrapper turns into an exit code.
    def run_test(**kwargs)
      result = nil
      @output = capture_stdout { result = cli.test(**kwargs) }
      result
    end

    it "prints one line per delivery result" do
      stub_notification([success, failure])

      output = capture_stdout { cli.test }

      expect(output).to match(/slack\s+success/)
      expect(output).to match(/webhook\s+failed\s+\(Net::OpenTimeout\)/)
    end

    it "never prints the delivery error message" do
      stub_notification([failure])

      expect(capture_stdout { cli.test }).not_to include("SECRET-TOKEN")
    end

    it "returns true when any channel succeeded" do
      stub_notification([success, failure])

      expect(run_test).to be true
    end

    it "returns false when every channel failed" do
      stub_notification([failure])

      expect(run_test).to be false
    end

    it "warns and returns false when no channel is configured" do
      stub_notification([])

      expect(run_test).to be false
      expect(@output).to include("No notification channels configured")
    end

    it "sends a transient preview that is never persisted" do
      stub_notification([success])

      expect { capture_stdout { cli.test } }.not_to change(SolidObserver::AlertHistory, :count).from(0)
      expect(SolidObserver::Services::AlertStatus.active_count).to eq(0)
    end

    it "passes an unsaved AlertHistory carrying only safe payload fields" do
      captured = nil
      allow(SolidObserver::Services::AlertNotification).to receive(:call) do |alert_history:, **|
        captured = alert_history
        [success]
      end

      capture_stdout { cli.test }

      expect(captured).to be_new_record
      expect(captured.payload.keys).to all(be_in(SolidObserver::AlertHistory::SAFE_PAYLOAD_FIELDS))
    end

    it "tags the preview with the test event type" do
      stub_notification([success])

      capture_stdout { cli.test }

      expect(SolidObserver::Services::AlertNotification).to have_received(:call)
        .with(hash_including(event_type: "test"))
    end

    it "forwards a single requested channel as a symbol" do
      SolidObserver.config.slack_webhook_url = "https://hooks.example.com/T000"
      stub_notification([success])

      capture_stdout { cli.test(channel: "slack") }

      expect(SolidObserver::Services::AlertNotification).to have_received(:call)
        .with(hash_including(channels: :slack))
    end

    # Naming a channel bypasses AlertNotification's `configured` predicate, so
    # without this guard the operator sees TypeError / KeyError instead of the
    # actual problem.
    it "reports a named channel that is not configured, without dispatching" do
      allow(SolidObserver::Services::AlertNotification).to receive(:call)

      expect(run_test(channel: "slack")).to be false
      expect(@output).to include("Channel slack is unknown or not configured")
      expect(SolidObserver::Services::AlertNotification).not_to have_received(:call)
    end

    it "reports an unknown channel name, without dispatching" do
      allow(SolidObserver::Services::AlertNotification).to receive(:call)

      expect(run_test(channel: "carrier-pigeon")).to be false
      expect(@output).to include("Channel carrier-pigeon is unknown or not configured")
      expect(SolidObserver::Services::AlertNotification).not_to have_received(:call)
    end

    it "auto-detects channels when none is requested" do
      stub_notification([success])

      capture_stdout { cli.test(channel: "") }

      expect(SolidObserver::Services::AlertNotification).to have_received(:call)
        .with(hash_including(channels: nil))
    end

    it "returns false without dispatching when alerts are disabled" do
      allow(SolidObserver.config).to receive(:alerts_enabled).and_return(false)
      allow(SolidObserver::Services::AlertNotification).to receive(:call)

      expect(run_test).to be false
      expect(@output).to include("Alerting is unavailable")
      expect(SolidObserver::Services::AlertNotification).not_to have_received(:call)
    end
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end
end
