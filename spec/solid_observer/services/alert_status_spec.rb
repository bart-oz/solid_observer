# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::AlertStatus do
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

  before do
    SolidObserver::AlertHistory.delete_all
    allow(SolidObserver.config).to receive(:realtime_mode?).and_return(false)
    allow(SolidObserver.config).to receive(:alerts_enabled).and_return(true)
  end

  describe ".active_count" do
    it "returns 0 when realtime mode is active" do
      allow(SolidObserver.config).to receive(:realtime_mode?).and_return(true)
      expect(described_class.active_count).to eq(0)
    end

    it "returns 0 when alerts are disabled" do
      allow(SolidObserver.config).to receive(:alerts_enabled).and_return(false)
      expect(described_class.active_count).to eq(0)
    end

    it "returns count of active alert histories when enabled" do
      rule = SolidObserver::AlertRule.create!(
        rule_name: "Status Test Rule",
        metric_type: "queue_latency",
        comparison_operator: ">",
        threshold_value: 10
      )
      SolidObserver::AlertHistory.create!(
        alert_rule: rule,
        triggered_at: Time.current,
        metric_value: 15,
        state: "triggered"
      )

      expect(described_class.active_count).to eq(1)
    end
  end
end
