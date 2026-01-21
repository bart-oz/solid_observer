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
        scope = scope.where(queue_name: queue) if queue
        scope = scope.where("job_class = ?", job_class) if job_class
        scope.order(created_at: :desc).limit(limit.to_i).to_a
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

      def format_job_row(job)
        [
          job.id.to_s,
          job.queue_name,
          job.job_class,
          job_status(job),
          format_time(job.created_at)
        ]
      end

      def job_status(job)
        return "Ready" if job.is_a?(SolidQueue::ReadyExecution)
        return "Scheduled" if job.is_a?(SolidQueue::ScheduledExecution)
        return "Claimed" if job.is_a?(SolidQueue::ClaimedExecution)
        return "Failed" if job.is_a?(SolidQueue::FailedExecution)

        "Unknown"
      end

      def format_time(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      def print_job_details(job)
        print_section_header("📄 Job Details")

        details = build_job_details(job)

        table(
          headers: ["Attribute", "Value"],
          rows: details
        )
        output("")
      end

      def build_job_details(job)
        details = [
          ["ID", job.id],
          ["Queue", job.queue_name],
          ["Class", job.job_class],
          ["Status", job_status(job)],
          ["Created At", format_time(job.created_at)],
          ["Priority", job.priority]
        ]

        add_scheduled_details(details, job)
        add_error_details(details, job)

        details
      end

      def add_scheduled_details(details, job)
        return unless job.is_a?(SolidQueue::ScheduledExecution)

        details << ["Scheduled At", format_time(job.scheduled_at)]
      end

      def add_error_details(details, job)
        return unless job.is_a?(SolidQueue::FailedExecution)
        return unless job.error

        details << ["Error", job.error.exception_class]
        details << ["Error Message", job.error.message]
      end

      def print_section_header(title)
        output("\n#{title}", color: :cyan)
        output("=" * 80, color: :cyan)
        output("")
      end
    end
  end
end
