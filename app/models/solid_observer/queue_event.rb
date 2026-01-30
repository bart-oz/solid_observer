# frozen_string_literal: true

module SolidObserver
  class QueueEvent < BaseEvent
    self.table_name = "solid_observer_queue_events"
  end
end
