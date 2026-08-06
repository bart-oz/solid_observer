# frozen_string_literal: true

class CreateSolidObserverAlertRules < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_alert_rules do |t|
      t.string :rule_name, null: false, limit: 120
      t.string :metric_type, null: false, limit: 50
      t.float :threshold_value, null: false
      t.string :comparison_operator, null: false, limit: 3
      t.integer :cooldown_minutes, null: false, default: 15
      t.boolean :enabled, null: false, default: true
      t.timestamps

      t.index :rule_name, unique: true, name: "idx_solid_observer_alert_rules_name_unique"
      t.index :enabled
      t.index [:metric_type, :enabled], name: "idx_solid_observer_alert_rules_eval"
    end
  end
end
