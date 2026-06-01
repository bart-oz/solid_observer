# frozen_string_literal: true

class CreateSolidObserverCacheEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_cache_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :key_digest, null: false, limit: 64
      t.boolean :hit
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false

      t.index :recorded_at
      t.index :event_type
      t.index :key_digest
      t.index :hit
      t.index :error_class
    end
  end
end
