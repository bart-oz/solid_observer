# frozen_string_literal: true

module SolidObserver
  class StorageInfo < BaseEvent
    self.table_name = "solid_observer_storage_info"

    MB_TO_BYTES = 1_048_576
    GB_TO_BYTES = 1_073_741_824
    COMPONENTS = %w[queue_observer cache_observer solid_cache].freeze

    validates :db_size_bytes, presence: true, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :event_count, presence: true, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :recorded_at, presence: true
    validates :component, presence: true, inclusion: {in: COMPONENTS}

    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
    scope :since, ->(time) { where("recorded_at >= ?", time) }

    def self.record_snapshot(db_size:, event_count:, component: "queue_observer")
      create!(
        component: component,
        db_size_bytes: db_size || 0,
        event_count: event_count,
        recorded_at: Time.current
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "[SolidObserver] Failed to record storage snapshot: #{e.message}"
      raise
    end

    def db_size_mb
      (db_size_bytes / MB_TO_BYTES.to_f).round(2)
    end

    def db_size_gb
      (db_size_bytes / GB_TO_BYTES.to_f).round(2)
    end
  end
end
