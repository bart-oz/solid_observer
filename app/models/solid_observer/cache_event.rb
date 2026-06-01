# frozen_string_literal: true

module SolidObserver
  class CacheEvent < BaseEvent
    self.table_name = "solid_observer_cache_events"

    validates :event_type, presence: true
    validates :key_digest, presence: true
    validates :recorded_at, presence: true

    scope :errored, -> { where.not(error_class: nil) }
    scope :slow, ->(threshold = SolidObserver.config.cache_slow_threshold) { where("duration >= ?", threshold) }
    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
  end
end
