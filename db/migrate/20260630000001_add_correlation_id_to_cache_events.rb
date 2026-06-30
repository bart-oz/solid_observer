# frozen_string_literal: true

class AddCorrelationIdToCacheEvents < ActiveRecord::Migration[8.0]
  def change
    add_column :solid_observer_cache_events, :correlation_id, :string, limit: 64
    # ponytail: PG-concurrent hardening (disable_ddl_transaction! + algorithm: :concurrently) if table size warrants; see 20260612000001
    add_index :solid_observer_cache_events, :correlation_id, where: "correlation_id IS NOT NULL"
  end
end
