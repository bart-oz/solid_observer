# frozen_string_literal: true

module SolidObserver
  module Queries
    class EventsQuery
      def initialize(filter)
        @filter = filter
      end

      def call
        event_type = @filter.event_type
        job_class = @filter.job_class
        queue_name = @filter.queue_name
        from = @filter.from
        to = @filter.to

        scope = QueueEvent.order(recorded_at: :desc)
        scope = scope.by_event_type(event_type) if event_type.present?
        scope = scope.by_job_class(job_class) if job_class.present?
        scope = scope.by_queue(queue_name) if queue_name.present?
        scope = scope.since(from.beginning_of_day) if from
        scope = scope.before(to.end_of_day) if to
        scope
      end
    end
  end
end
