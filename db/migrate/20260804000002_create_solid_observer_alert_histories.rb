# frozen_string_literal: true

class CreateSolidObserverAlertHistories < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_alert_histories do |t|
      t.bigint :alert_rule_id, null: false
      t.datetime :triggered_at, null: false
      t.datetime :resolved_at
      t.float :metric_value, null: false
      t.string :state, null: false, limit: 16
      t.text :payload
      t.timestamps

      t.index :alert_rule_id, name: "idx_solid_observer_alert_histories_rule"
      t.index :triggered_at
      t.index :state
      t.index [:alert_rule_id], unique: true, where: "state = 'triggered'", name: "idx_solid_observer_alert_histories_active_unique"
    end
  end
end
