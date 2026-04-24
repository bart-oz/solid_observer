# frozen_string_literal: true

class AddCompositeIndexesToQueueEvents < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    options = concurrent_supported? ? {algorithm: :concurrently} : {}

    add_index :solid_observer_queue_events,
      %i[job_class recorded_at],
      order: {recorded_at: :desc},
      if_not_exists: true,
      **options

    add_index :solid_observer_queue_events,
      %i[queue_name recorded_at],
      order: {recorded_at: :desc},
      if_not_exists: true,
      **options

    remove_index :solid_observer_queue_events, :job_class, if_exists: true, **options
    remove_index :solid_observer_queue_events, :queue_name, if_exists: true, **options
  end

  private

  def concurrent_supported?
    connection.adapter_name.match?(/postgres/i)
  end
end
