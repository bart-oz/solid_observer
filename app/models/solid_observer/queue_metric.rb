# frozen_string_literal: true

module SolidObserver
  class QueueMetric < BaseMetric
    self.abstract_class = true
    connects_to database: {writing: :solid_observer_queue, reading: :solid_observer_queue}
  end
end
