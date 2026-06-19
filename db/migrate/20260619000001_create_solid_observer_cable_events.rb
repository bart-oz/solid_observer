# frozen_string_literal: true

class CreateSolidObserverCableEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :channel_class, limit: 255
      t.string :broadcasting_digest, limit: 64
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false

      t.index :recorded_at
      t.index :event_type
      t.index :channel_class
      t.index :broadcasting_digest
      t.index :error_class
    end
  end
end
