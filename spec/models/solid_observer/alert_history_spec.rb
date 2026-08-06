# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::AlertHistory do
  before(:all) do
    connection = described_class.connection

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
    described_class.reset_column_information
  end

  before { described_class.delete_all }

  let(:alert_rule) do
    SolidObserver::AlertRule.create!(
      rule_name: "history-rule-#{SolidObserver::AlertRule.count + 1}",
      metric_type: "queue_latency",
      threshold_value: 5.0,
      comparison_operator: ">"
    )
  end

  let(:valid_attributes) do
    {
      alert_rule: alert_rule,
      triggered_at: Time.current,
      metric_value: 6.0,
      state: "triggered"
    }
  end

  it "inherits from BaseRecord" do
    expect(described_class.superclass).to eq(SolidObserver::BaseRecord)
  end

  it "uses solid_observer_alert_histories table" do
    expect(described_class.table_name).to eq("solid_observer_alert_histories")
  end

  it "is invalid without alert_rule, triggered_at, metric_value, or state" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors[:alert_rule]).to be_present
    expect(record.errors[:triggered_at]).to be_present
    expect(record.errors[:metric_value]).to be_present
    expect(record.errors[:state]).to be_present
  end

  it "rejects unsupported states and accepts every supported state" do
    invalid_record = described_class.new(valid_attributes.merge(state: "firing"))

    expect(invalid_record).not_to be_valid
    expect(invalid_record.errors[:state]).to be_present

    described_class::STATES.each do |state|
      record = described_class.new(valid_attributes.merge(state: state))

      expect(record).to be_valid
    end
  end

  it "returns only triggered rows from the active scope" do
    triggered_history = described_class.create!(valid_attributes)
    resolved_history = described_class.create!(valid_attributes.merge(state: "resolved"))

    expect(described_class.active).to contain_exactly(triggered_history)
    expect(resolved_history.state).to eq("resolved")
  end

  it "orders recent rows by triggered_at descending and honors the limit" do
    oldest = described_class.create!(valid_attributes.merge(triggered_at: Time.utc(2026, 8, 4, 10, 0, 0)))
    middle = described_class.create!(valid_attributes.merge(state: "resolved", triggered_at: Time.utc(2026, 8, 4, 11, 0, 0)))
    newest = described_class.create!(valid_attributes.merge(state: "resolved", triggered_at: Time.utc(2026, 8, 4, 12, 0, 0)))

    expect(described_class.recent(2).to_a).to eq([newest, middle])
    expect(described_class.recent.to_a).to eq([newest, middle, oldest])
  end

  it "resolves an active history with the current time" do
    history = described_class.create!(valid_attributes)

    travel_to(Time.utc(2026, 8, 4, 12, 0, 0)) do
      history.resolve!

      expect(history.reload.state).to eq("resolved")
      expect(history.resolved_at).to eq(Time.current)
    end
  end

  it "returns only approved payload fields" do
    approved_payload = {
      "rule_name" => "queue-latency",
      "metric_type" => "queue_latency",
      "metric_value" => 6.0,
      "threshold_value" => 5.0,
      "triggered_at" => "2026-08-04T12:00:00Z",
      "environment" => "test",
      "severity" => "warning"
    }
    raw_payload = approved_payload.merge(
      "error_message" => "private exception",
      "metadata" => {"request_id" => "secret"},
      "job_arguments" => ["private argument"],
      "cache_key" => "private-cache-key",
      "cable_payload" => {"message" => "private"}
    )
    history = described_class.create!(valid_attributes)
    history.update_column(:payload, JSON.generate(raw_payload))

    sanitized_payload = history.reload.payload

    expect(sanitized_payload).to eq(approved_payload)
    expect(sanitized_payload).not_to have_key("error_message")
    expect(sanitized_payload).not_to have_key("metadata")
    expect(sanitized_payload).not_to have_key("job_arguments")
    expect(sanitized_payload).not_to have_key("cache_key")
    expect(sanitized_payload).not_to have_key("cable_payload")
  end

  it "returns an empty payload for malformed JSON and nil columns" do
    malformed_history = described_class.create!(valid_attributes)
    nil_payload_history = described_class.create!(valid_attributes.merge(state: "resolved"))
    malformed_history.update_column(:payload, "{")
    nil_payload_history.update_column(:payload, nil)

    expect(malformed_history.reload.payload).to eq({})
    expect(nil_payload_history.reload.payload).to eq({})
  end

  it "returns an empty payload for non-object JSON roots" do
    record = described_class.create!(valid_attributes)

    ["[1,2]", "5", "true", "null", '"str"'].each do |raw|
      record.update_column(:payload, raw)
      record.reload

      expect(record.payload).to eq({})
    end
  end

  it "deletes histories when its alert rule is deleted" do
    history = described_class.create!(valid_attributes)

    alert_rule.destroy

    expect(described_class.where(id: history.id)).to be_empty
  end
end
