# frozen_string_literal: true

module SolidObserver
  module Queries
    class JobExecutionsQuery
      STATUS_SCOPES = {
        "ready" => -> { SolidQueue::ReadyExecution.all },
        "scheduled" => -> { SolidQueue::ScheduledExecution.all },
        "claimed" => -> { SolidQueue::ClaimedExecution.all },
        "failed" => -> { SolidQueue::FailedExecution.all }
      }.freeze

      def initialize(filter)
        @filter = filter
      end

      def call
        status = @filter.status
        scope = STATUS_SCOPES.fetch(status, STATUS_SCOPES["ready"]).call
        scope = apply_queue_filter(scope, status)
        scope = apply_job_class_filter(scope)
        scope.order(created_at: :desc)
      end

      private

      def apply_job_class_filter(scope)
        job_class = @filter.job_class
        return scope if job_class.blank?

        scope.joins(:job).where(solid_queue_jobs: {class_name: job_class})
      end

      def apply_queue_filter(scope, status)
        queue_name = @filter.queue_name
        return scope if queue_name.blank?

        if %w[failed claimed].include?(status)
          scope.joins(:job).where(solid_queue_jobs: {queue_name: queue_name})
        else
          scope.where(queue_name: queue_name)
        end
      end
    end
  end
end
