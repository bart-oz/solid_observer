# frozen_string_literal: true

class AddCorrelationIdToCableEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_observer_cable_events, :correlation_id, :string, limit: 64
    add_index :solid_observer_cable_events, :correlation_id, where: "correlation_id IS NOT NULL"
  end
end
