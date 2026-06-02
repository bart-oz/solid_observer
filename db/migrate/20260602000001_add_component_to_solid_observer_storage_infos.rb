# frozen_string_literal: true

class AddComponentToSolidObserverStorageInfos < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_observer_storage_info, :component, :string, null: false, default: "queue_observer"
    add_index :solid_observer_storage_info, :component
  end
end
