# frozen_string_literal: true

class AddEventTypeRecordedAtIndexToCacheEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    options = concurrent_supported? ? {algorithm: :concurrently} : {}

    add_index :solid_observer_cache_events,
      %i[event_type recorded_at],
      order: {recorded_at: :desc},
      if_not_exists: true,
      **options
  end

  private

  def concurrent_supported?
    connection.adapter_name.match?(/postgres/i)
  end
end
