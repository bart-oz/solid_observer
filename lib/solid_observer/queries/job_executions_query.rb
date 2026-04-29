# frozen_string_literal: true

module SolidObserver
  module Queries
    class JobExecutionsQuery
      ALL_ACTIVE_STATUSES = %w[ready scheduled claimed failed].freeze

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
        return all_active_executions if status == "all_active"

        filtered_scope(status).order(created_at: :desc)
      end

      private

      def all_active_executions
        records = all_active_records.sort_by(&:created_at).reverse
        preload_jobs(records)
      end

      def all_active_records
        ALL_ACTIVE_STATUSES.flat_map do |status|
          filtered_scope(status).order(created_at: :desc).limit(50).to_a
        end
      end

      def preload_jobs(records)
        ActiveRecord::Associations::Preloader.new(records:, associations: :job).call
        records
      end

      def filtered_scope(status)
        scope = status_scope(status)
        scope = apply_queue_filter(scope, status)
        apply_job_class_filter(scope)
      end

      def status_scope(status)
        STATUS_SCOPES.fetch(status, STATUS_SCOPES["ready"]).call
      end

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
