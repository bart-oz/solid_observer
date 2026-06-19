# frozen_string_literal: true

module SolidObserver
  class CableEvent < BaseEvent
    self.table_name = "solid_observer_cable_events"

    validates :event_type, presence: true
    validates :recorded_at, presence: true

    scope :errored, -> { where.not(error_class: nil) }
    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
  end
end
