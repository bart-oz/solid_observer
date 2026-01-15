# frozen_string_literal: true

class CreateSolidObserverMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_metrics do |t|
      t.string :metric_name, null: false, limit: 50
      t.bigint :value, null: false, default: 0
      t.datetime :period_start, null: false
      t.string :period_type, null: false, limit: 10

      t.index [:metric_name, :period_start, :period_type],
        unique: true,
        name: "idx_solid_observer_metrics_unique"
    end
  end
end
