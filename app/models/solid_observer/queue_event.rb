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
    DISTINCT_FILTER_LIMIT = 500

    validates :event_type, presence: true, inclusion: {in: EVENT_TYPES}
    validates :recorded_at, presence: true

    scope :by_job_class, ->(job_class) { where(job_class: job_class) }
    scope :by_queue, ->(queue_name) { where(queue_name: queue_name) }
    scope :by_event_type, ->(event_type) { where(event_type: event_type) }
    scope :since, ->(time) { where("recorded_at >= ?", time) }
    scope :before, ->(time) { where("recorded_at < ?", time) }
    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
    scope :recent_failures, ->(limit = 5) { by_event_type("job_failed").order(recorded_at: :desc).limit(limit) }
    scope :distinct_job_classes, -> {
      where("recorded_at >= ?", SolidObserver.config.event_retention.ago)
        .where.not(job_class: nil)
        .distinct
        .limit(DISTINCT_FILTER_LIMIT)
        .pluck(:job_class)
        .sort
    }
    scope :distinct_queue_names, -> {
      where("recorded_at >= ?", SolidObserver.config.event_retention.ago)
        .where.not(queue_name: nil)
        .distinct
        .limit(DISTINCT_FILTER_LIMIT)
        .pluck(:queue_name)
        .sort
    }
  end
end
