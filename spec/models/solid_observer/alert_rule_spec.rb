# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::AlertRule do
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
    described_class.reset_column_information
  end

  before { described_class.delete_all }

  let(:valid_attributes) do
    {
      rule_name: "queue-latency",
      metric_type: "queue_latency",
      threshold_value: 5.0,
      comparison_operator: ">"
    }
  end

  it "inherits from BaseRecord" do
    expect(described_class.superclass).to eq(SolidObserver::BaseRecord)
  end

  it "uses solid_observer_alert_rules table" do
    expect(described_class.table_name).to eq("solid_observer_alert_rules")
  end

  it "is invalid without required attributes" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors[:rule_name]).to be_present
    expect(record.errors[:metric_type]).to be_present
    expect(record.errors[:comparison_operator]).to be_present
    expect(record.errors[:threshold_value]).to be_present
  end

  it "defaults cooldown_minutes to 15 on persisted records" do
    record = described_class.create!(valid_attributes)

    expect(record.cooldown_minutes).to eq(15)
  end

  it "rejects unsupported metric types and accepts every supported metric type" do
    invalid_record = described_class.new(valid_attributes.merge(metric_type: "unknown"))

    expect(invalid_record).not_to be_valid
    expect(invalid_record.errors[:metric_type]).to be_present

    described_class::METRIC_TYPES.each do |metric_type|
      record = described_class.new(valid_attributes.merge(rule_name: "rule-#{metric_type}", metric_type: metric_type))

      expect(record).to be_valid
    end
  end

  it "rejects unsupported comparison operators and accepts every supported operator" do
    invalid_record = described_class.new(valid_attributes.merge(comparison_operator: "!="))

    expect(invalid_record).not_to be_valid
    expect(invalid_record.errors[:comparison_operator]).to be_present

    described_class::COMPARISON_OPERATORS.each_with_index do |operator, index|
      record = described_class.new(valid_attributes.merge(rule_name: "operator-rule-#{index}", comparison_operator: operator))

      expect(record).to be_valid
    end
  end

  it "enforces unique rule names" do
    described_class.create!(valid_attributes)
    duplicate = described_class.new(valid_attributes)

    expect(duplicate).not_to be_valid
    expect(duplicate.errors[:rule_name]).to be_present
  end

  it "returns only enabled rows from the enabled scope" do
    enabled_rule = described_class.create!(valid_attributes)
    disabled_rule = described_class.create!(valid_attributes.merge(rule_name: "disabled-rule", enabled: false))

    enabled_rules = described_class.enabled

    expect(enabled_rules).to be_a(ActiveRecord::Relation)
    expect(enabled_rules).to contain_exactly(enabled_rule)
    expect(enabled_rule.enabled).to be(true)
    expect(disabled_rule.enabled).to be(false)
  end
end
