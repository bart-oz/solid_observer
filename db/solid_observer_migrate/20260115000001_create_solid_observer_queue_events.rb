# frozen_string_literal: true

class CreateSolidObserverQueueEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_queue_events do |t|
      t.string :event_type, null: false, limit: 50
      t.string :job_class, limit: 100
      t.string :queue_name, limit: 50
      t.string :correlation_id, limit: 64
      t.text :metadata
      t.float :duration
      t.datetime :recorded_at, null: false

      t.index :recorded_at
      t.index :correlation_id, where: "correlation_id IS NOT NULL"
      t.index :event_type
      t.index :job_class
      t.index :queue_name
    end
  end
end
