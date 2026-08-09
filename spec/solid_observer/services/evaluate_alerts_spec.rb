# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::EvaluateAlerts do
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

  let(:queue_snapshot) do
    {ready: 5, scheduled: 5, failed_last_hour: 2, performed_last_hour: 8}
  end

  let(:health_response) do
    {overall: :stable, components: {}}
  end

  let(:logger) { instance_double(ActiveSupport::Logger) }

  before do
    SolidObserver::AlertHistory.delete_all
    SolidObserver::AlertRule.delete_all
    allow(Rails).to receive(:logger).and_return(logger)
    allow(logger).to receive(:warn)
    allow(SolidObserver.config).to receive(:realtime_mode?).and_return(false)
    allow(SolidObserver.config).to receive(:alerts_enabled).and_return(true)
    allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(queue_snapshot)
    allow(SolidObserver::Services::HealthScore).to receive(:call).and_return(health_response)
    allow(SolidObserver::Services::DatabaseSize).to receive(:call).and_return(1024)
    allow(SolidObserver::NotificationDeliveryJob).to receive(:perform_later)
  end

  describe ".call" do
    context "when realtime mode or alerts disabled" do
      it "skips evaluation when in realtime mode" do
        allow(SolidObserver.config).to receive(:realtime_mode?).and_return(true)
        result = described_class.call

        expect(logger).to have_received(:warn).with(/EvaluateAlerts skipped: realtime mode/)
        expect(result[:skipped]).to be true
      end

      it "skips evaluation when alerts disabled" do
        allow(SolidObserver.config).to receive(:alerts_enabled).and_return(false)
        result = described_class.call

        expect(logger).to have_received(:warn).with(/EvaluateAlerts skipped: alerts disabled/)
        expect(result[:skipped]).to be true
      end
    end

    context "when evaluating enabled rules" do
      let!(:rule) do
        SolidObserver::AlertRule.create!(
          rule_name: "High Queue Latency",
          metric_type: "queue_latency",
          comparison_operator: ">",
          threshold_value: 8,
          cooldown_minutes: 15
        )
      end

      it "evaluates metrics in a memoized pass and triggers alert on breach" do
        expect(SolidObserver::QueueStats).to receive(:snapshot).once.and_return(queue_snapshot)

        result = described_class.call

        expect(result[:triggered]).to eq(1)
        history = SolidObserver::AlertHistory.last
        expect(history.state).to eq("triggered")
        expect(history.metric_value).to eq(10)
        expect(SolidObserver::NotificationDeliveryJob).to have_received(:perform_later).with(history.id, "triggered")
      end

      it "does not trigger alert if an active alert already exists" do
        SolidObserver::AlertHistory.create!(
          alert_rule: rule,
          triggered_at: Time.current,
          metric_value: 15,
          state: "triggered"
        )

        result = described_class.call
        expect(result[:triggered]).to eq(0)
      end

      it "does not trigger alert if cooldown is active" do
        SolidObserver::AlertHistory.create!(
          alert_rule: rule,
          triggered_at: 10.minutes.ago,
          metric_value: 15,
          state: "resolved",
          resolved_at: 5.minutes.ago
        )

        result = described_class.call
        expect(result[:triggered]).to eq(0)
      end

      it "resolves active alert when metric returns to normal bounds" do
        active_history = SolidObserver::AlertHistory.create!(
          alert_rule: rule,
          triggered_at: 20.minutes.ago,
          metric_value: 15,
          state: "triggered"
        )
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return({ready: 2, scheduled: 2, performed_in_range: 10, failed_in_range: 0})
        result = described_class.call
        expect(result[:resolved]).to eq(1)
        expect(active_history.reload.state).to eq("resolved")
        expect(SolidObserver::NotificationDeliveryJob).to have_received(:perform_later).with(active_history.id, "resolved")
      end

      it "evaluates health_score metric correctly when health is degraded or critical" do
        health_rule = SolidObserver::AlertRule.create!(
          rule_name: "Health Degraded",
          metric_type: "health_score",
          comparison_operator: ">=",
          threshold_value: 1,
          cooldown_minutes: 15
        )
        allow(SolidObserver::Services::HealthScore).to receive(:call).and_return({overall: :degraded, components: {}})
        described_class.call
        history = SolidObserver::AlertHistory.find_by(alert_rule: health_rule)
        expect(history).to be_present
        expect(history.state).to eq("triggered")
        expect(history.metric_value).to eq(1)
      end

      it "evaluates error_rate metric correctly with throughput snapshot keys" do
        error_rule = SolidObserver::AlertRule.create!(
          rule_name: "High Error Rate",
          metric_type: "error_rate",
          comparison_operator: ">",
          threshold_value: 0.1,
          cooldown_minutes: 15
        )
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return({
          ready: 0, scheduled: 0, performed_in_range: 80, failed_in_range: 20
        })

        result = described_class.call
        expect(result[:triggered]).to eq(1)
        history = SolidObserver::AlertHistory.find_by(alert_rule: error_rule)
        expect(history.metric_value).to eq(0.2)
      end
    end
  end
end
