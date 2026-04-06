# frozen_string_literal: true

module SolidObserver
  class QueueEvent < BaseEvent
    self.table_name = "solid_observer_queue_events"

    EVENT_TYPES = %w[
      job_enqueued
      job_completed
      job_failed
      job_discarded
    ].freeze

    validates :event_type, presence: true, inclusion: {in: EVENT_TYPES}
    validates :recorded_at, presence: true

    scope :by_job_class, ->(job_class) { where(job_class: job_class) }
    scope :by_queue, ->(queue_name) { where(queue_name: queue_name) }
    scope :by_event_type, ->(event_type) { where(event_type: event_type) }
    scope :since, ->(time) { where("recorded_at >= ?", time) }
    scope :before, ->(time) { where("recorded_at < ?", time) }
    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
    scope :recent_failures, ->(limit = 5) { by_event_type("job_failed").order(recorded_at: :desc).limit(limit) }
  end
end
