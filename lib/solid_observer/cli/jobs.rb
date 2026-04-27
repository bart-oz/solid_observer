# frozen_string_literal: true

module SolidObserver
  module CLI
    class Jobs < Base
      def list(status: nil, queue: nil, job_class: nil, limit: 20)
        return error("SolidQueue is not available") unless solid_queue_available?

        jobs = fetch_jobs(status: status, queue: queue, job_class: job_class, limit: limit)

        return warning("No jobs found matching the criteria") if jobs.empty?

        print_jobs_table(jobs)
      end

      def show(job_id)
        return error("SolidQueue is not available") unless solid_queue_available?

        job = find_job(job_id)
        return unless job

        print_job_details(job)
      end

      def retry_job(job_id)
        return error("SolidQueue is not available") unless solid_queue_available?

        job = find_failed_job(job_id)
        return unless job

        return info("Retry cancelled") unless confirm("Retry job #{job_id}?")

        job.retry
        success("✓ Job #{job_id} has been queued for retry")
      end

      def discard(job_id)
        return error("SolidQueue is not available") unless solid_queue_available?

        job = find_failed_job(job_id)
        return unless job

        return info("Discard cancelled") unless confirm("Discard job #{job_id}? This cannot be undone.", default: false)

        job.discard
        success("✓ Job #{job_id} has been discarded")
      end

      private

      def solid_queue_available?
        SolidObserver::QueueStats.solid_queue_available?
      end

      def fetch_jobs(status:, queue:, job_class:, limit:)
        scope = scope_for_status(status)
        scope = scope.joins(:job) if job_class || needs_job_join?(status, queue)
        scope = apply_queue_filter(scope, status, queue)
        scope = scope.where("solid_queue_jobs.class_name = ?", job_class) if job_class
        scope.order(created_at: :desc).limit(limit.to_i).includes(:job).to_a
      end

      def needs_job_join?(status, queue)
        queue && %w[failed claimed].include?(status&.to_s&.downcase)
      end

      def apply_queue_filter(scope, status, queue)
        return scope unless queue

        case status&.to_s&.downcase
        when "failed", "claimed"
          scope.where("solid_queue_jobs.queue_name = ?", queue)
        else
          scope.where(queue_name: queue)
        end
      end

      def scope_for_status(status)
        case status&.to_s&.downcase
        when "ready" then SolidQueue::ReadyExecution.all
        when "scheduled" then SolidQueue::ScheduledExecution.all
        when "claimed" then SolidQueue::ClaimedExecution.all
        when "failed" then SolidQueue::FailedExecution.all
        else SolidQueue::ReadyExecution.all
        end
      end

      def find_job(job_id)
        job = find_in_execution_tables(job_id)
        return job if job

        error("Job #{job_id} not found")
        nil
      end

      def find_failed_job(job_id)
        job = SolidQueue::FailedExecution.find_by(id: job_id)
        return job if job

        error("Failed job #{job_id} not found")
        nil
      end

      def find_in_execution_tables(job_id)
        SolidQueue::ReadyExecution.find_by(id: job_id) ||
          SolidQueue::ScheduledExecution.find_by(id: job_id) ||
          SolidQueue::ClaimedExecution.find_by(id: job_id) ||
          SolidQueue::FailedExecution.find_by(id: job_id)
      end

      def print_jobs_table(jobs)
        print_section_header("📋 Jobs")
        table(
          headers: ["ID", "Queue", "Class", "Status", "Created At"],
          rows: jobs.map { |job| format_job_row(job) }
        )
        output("")
      end

      def format_job_row(execution)
        job = execution.job
        [
          execution.id.to_s,
          job&.queue_name || execution.try(:queue_name) || "N/A",
          job&.class_name || "N/A",
          job_status(execution),
          format_time(execution.created_at)
        ]
      end

      def job_status(execution)
        return "Ready" if execution.is_a?(SolidQueue::ReadyExecution)
        return "Scheduled" if execution.is_a?(SolidQueue::ScheduledExecution)
        return "Claimed" if execution.is_a?(SolidQueue::ClaimedExecution)
        return "Failed" if execution.is_a?(SolidQueue::FailedExecution)

        "Unknown"
      end

      def format_time(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      def print_job_details(execution)
        print_section_header("📄 Job Details")

        details = build_job_details(execution)

        table(
          headers: ["Attribute", "Value"],
          rows: details
        )
        output("")
      end

      def build_job_details(execution)
        job = execution.job
        details = [
          ["ID", execution.id],
          ["Job ID", job&.id || "N/A"],
          ["Queue", job&.queue_name || execution.try(:queue_name) || "N/A"],
          ["Class", job&.class_name || "N/A"],
          ["Status", job_status(execution)],
          ["Created At", format_time(execution.created_at)],
          ["Priority", execution.try(:priority) || job&.priority || "N/A"]
        ]

        add_scheduled_details(details, execution)
        add_error_details(details, execution)

        details
      end

      def add_scheduled_details(details, execution)
        return unless execution.is_a?(SolidQueue::ScheduledExecution)

        details << ["Scheduled At", format_time(execution.scheduled_at)]
      end

      def add_error_details(details, execution)
        return unless execution.is_a?(SolidQueue::FailedExecution)
        return unless execution.error

        details << ["Error", execution.error.exception_class]
        details << ["Error Message", execution.error.message]
      end

      def print_section_header(title)
        output("\n#{title}", color: :red)
        output("=" * 80, color: :red)
        output("")
      end
    end
  end
end
