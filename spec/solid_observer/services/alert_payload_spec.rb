# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::AlertPayload do
  before(:all) do
    connection = SolidObserver::AlertHistory.connection
    unless connection.table_exists?(:solid_observer_alert_histories)
      connection.create_table :solid_observer_alert_histories do |t|
        t.bigint :alert_rule_id, null: false
        t.datetime :triggered_at, null: false
        t.datetime :resolved_at
        t.float :metric_value, null: false
        t.string :state, null: false, limit: 16
        t.text :payload
        t.timestamps
      end
    end
    SolidObserver::AlertHistory.reset_column_information
    SolidObserver::AlertHistory.define_attribute_methods
  end

  after { SolidObserver.reset_configuration! }

  let(:triggered_at) { Time.current }

  let(:alert_history) do
    instance_double(
      SolidObserver::AlertHistory,
      payload: {"rule_name" => "High error rate", "severity" => "critical", "metric_type" => "error_rate", "environment" => "production"},
      metric_value: 0.42,
      triggered_at: triggered_at,
      state: "triggered"
    )
  end

  describe ".call" do
    it "builds a payload with only the safe fields plus event_type and deep_link_url" do
      result = described_class.call(alert_history: alert_history)

      expect(result).to eq(
        rule_name: "High error rate",
        severity: "critical",
        metric_type: "error_rate",
        metric_value: 0.42,
        triggered_at: triggered_at,
        environment: "production",
        deep_link_url: "/solid_observer",
        event_type: "triggered"
      )
    end

    it "defaults event_type to alert_history.state when not given" do
      result = described_class.call(alert_history: alert_history)

      expect(result[:event_type]).to eq("triggered")
    end

    it "uses the given event_type over alert_history.state" do
      result = described_class.call(alert_history: alert_history, event_type: "resolved")

      expect(result[:event_type]).to eq("resolved")
    end

    context "when notification_base_url is configured" do
      before { SolidObserver.config.notification_base_url = "https://app.example.com" }

      it "builds an absolute deep_link_url" do
        result = described_class.call(alert_history: alert_history)

        expect(result[:deep_link_url]).to eq("https://app.example.com/solid_observer")
      end
    end

    context "when notification_base_url is blank" do
      it "falls back to a relative deep_link_url and logs a warning" do
        logger = instance_double(Logger, warn: nil)
        allow(Rails).to receive(:logger).and_return(logger)

        result = described_class.call(alert_history: alert_history)

        expect(logger).to have_received(:warn).with(/notification_base_url/)
        expect(result[:deep_link_url]).to eq("/solid_observer")
      end
    end
  end
end
