# frozen_string_literal: true

class CreateSolidObserverStorageInfo < ActiveRecord::Migration[8.0]
  def change
    create_table :solid_observer_storage_info do |t|
      t.bigint :db_size_bytes, null: false
      t.bigint :event_count, null: false
      t.datetime :recorded_at, null: false

      t.index :recorded_at
    end
  end
end
