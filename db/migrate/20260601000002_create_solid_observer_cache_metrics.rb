# frozen_string_literal: true

class CreateSolidObserverCacheMetrics < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_cache_metrics do |t|
      t.string :event_type, null: false, limit: 64
      t.datetime :period_start, null: false
      t.bigint :operations_count, null: false, default: 0
      t.bigint :hits_count, null: false, default: 0
      t.bigint :misses_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
      t.float :duration_total, null: false, default: 0.0

      t.index [:event_type, :period_start], unique: true, name: "idx_solid_observer_cache_metrics_unique"
      t.index :period_start
    end
  end
end
