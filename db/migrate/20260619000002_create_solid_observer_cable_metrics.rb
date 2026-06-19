# frozen_string_literal: true

class CreateSolidObserverCableMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_cable_metrics do |t|
      t.datetime :period_start, null: false
      t.bigint :broadcasts_count, null: false, default: 0
      t.bigint :transmissions_count, null: false, default: 0
      t.bigint :confirmations_count, null: false, default: 0
      t.bigint :rejections_count, null: false, default: 0
      t.bigint :perform_actions_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0

      t.index :period_start, unique: true, name: "idx_solid_observer_cable_metrics_unique"
    end
  end
end
