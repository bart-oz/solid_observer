# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Jobs do
  let(:jobs_cli) { described_class.new }

  before do
    stub_const("SolidQueue", Module.new)
    stub_const("SolidQueue::Job", Class.new)
    stub_const("SolidQueue::ReadyExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::ScheduledExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::ClaimedExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::FailedExecution", Class.new(ActiveRecord::Base))

    allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(true)
  end

  describe "#list" do
    context "when SolidQueue is not available" do
      before do
        allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.list }

        expect(output).to include("SolidQueue is not available")
      end
    end

    context "when SolidQueue is available" do
      let(:job1) do
        double("Job",
          id: 1,
          queue_name: "default",
          job_class: "TestJob",
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          priority: 0)
      end

      let(:job2) do
        double("Job",
          id: 2,
          queue_name: "mailers",
          job_class: "MailerJob",
          created_at: Time.new(2026, 1, 21, 11, 0, 0),
          priority: 5)
      end

      context "with no filters" do
        before do
          scope = double("scope")
          allow(SolidQueue::ReadyExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:order).and_return(scope)
          allow(scope).to receive(:limit).and_return(scope)
          allow(scope).to receive(:to_a).and_return([job1, job2])
          allow(job1).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
          allow(job1).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
          allow(job2).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
          allow(job2).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job2).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job2).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
        end

        it "displays jobs table" do
          output = capture_stdout { jobs_cli.list }

          expect(output).to include("📋 Jobs")
          expect(output).to include("ID")
          expect(output).to include("Queue")
          expect(output).to include("Class")
          expect(output).to include("Status")
          expect(output).to include("default")
          expect(output).to include("TestJob")
          expect(output).to include("Ready")
        end
      end

      context "with status filter" do
        before do
          scope = double("scope")
          allow(SolidQueue::FailedExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:order).and_return(scope)
          allow(scope).to receive(:limit).and_return(scope)
          allow(scope).to receive(:to_a).and_return([job1])
          allow(job1).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(true)
        end

        it "fetches jobs with specified status" do
          output = capture_stdout { jobs_cli.list(status: "failed") }

          expect(output).to include("Failed")
        end
      end

      context "with queue filter" do
        before do
          scope = double("scope")
          filtered_scope = double("filtered_scope")
          allow(SolidQueue::ReadyExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:where).with(queue_name: "mailers").and_return(filtered_scope)
          allow(filtered_scope).to receive(:order).and_return(filtered_scope)
          allow(filtered_scope).to receive(:limit).and_return(filtered_scope)
          allow(filtered_scope).to receive(:to_a).and_return([job2])
          allow(job2).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
          allow(job2).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job2).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job2).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
        end

        it "fetches jobs from specified queue" do
          output = capture_stdout { jobs_cli.list(queue: "mailers") }

          expect(output).to include("mailers")
          expect(output).to include("MailerJob")
        end
      end

      context "with job_class filter" do
        before do
          scope = double("scope")
          filtered_scope = double("filtered_scope")
          allow(SolidQueue::ReadyExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:where).with("job_class = ?", "TestJob").and_return(filtered_scope)
          allow(filtered_scope).to receive(:order).and_return(filtered_scope)
          allow(filtered_scope).to receive(:limit).and_return(filtered_scope)
          allow(filtered_scope).to receive(:to_a).and_return([job1])
          allow(job1).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
          allow(job1).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
        end

        it "fetches jobs of specified class" do
          output = capture_stdout { jobs_cli.list(job_class: "TestJob") }

          expect(output).to include("TestJob")
        end
      end

      context "with limit" do
        before do
          scope = double("scope")
          limited_scope = double("limited_scope")
          allow(SolidQueue::ReadyExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:order).and_return(scope)
          allow(scope).to receive(:limit).with(5).and_return(limited_scope)
          allow(limited_scope).to receive(:to_a).and_return([job1])
          allow(job1).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
          allow(job1).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
          allow(job1).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
        end

        it "limits number of jobs returned" do
          output = capture_stdout { jobs_cli.list(limit: 5) }

          expect(output).to include("TestJob")
        end
      end

      context "when no jobs found" do
        before do
          scope = double("scope")
          allow(SolidQueue::ReadyExecution).to receive(:all).and_return(scope)
          allow(scope).to receive(:order).and_return(scope)
          allow(scope).to receive(:limit).and_return(scope)
          allow(scope).to receive(:to_a).and_return([])
        end

        it "displays warning message" do
          output = capture_stdout { jobs_cli.list }

          expect(output).to include("No jobs found matching the criteria")
        end
      end
    end
  end

  describe "#show" do
    context "when SolidQueue is not available" do
      before do
        allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.show(1) }

        expect(output).to include("SolidQueue is not available")
      end
    end

    context "when job exists" do
      let(:job) do
        double("Job",
          id: 1,
          queue_name: "default",
          job_class: "TestJob",
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          priority: 0)
      end

      before do
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(job).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
        allow(job).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
      end

      it "displays job details" do
        output = capture_stdout { jobs_cli.show(1) }

        expect(output).to include("📄 Job Details")
        expect(output).to include("ID")
        expect(output).to include("1")
        expect(output).to include("Queue")
        expect(output).to include("default")
        expect(output).to include("Class")
        expect(output).to include("TestJob")
        expect(output).to include("Status")
        expect(output).to include("Ready")
      end
    end

    context "when job is scheduled" do
      let(:job) do
        double("Job",
          id: 1,
          queue_name: "default",
          job_class: "TestJob",
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          priority: 0,
          scheduled_at: Time.new(2026, 1, 21, 12, 0, 0))
      end

      before do
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(job).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(true)
        allow(job).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
      end

      it "displays scheduled_at field" do
        output = capture_stdout { jobs_cli.show(1) }

        expect(output).to include("Scheduled At")
        expect(output).to include("2026-01-21 12:00:00")
      end
    end

    context "when job is failed" do
      let(:error) { double("Error", exception_class: "StandardError", message: "Test error") }
      let(:job) do
        double("Job",
          id: 1,
          queue_name: "default",
          job_class: "TestJob",
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          priority: 0,
          error: error)
      end

      before do
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(job).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(job).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(true)
      end

      it "displays error information" do
        output = capture_stdout { jobs_cli.show(1) }

        expect(output).to include("Error")
        expect(output).to include("StandardError")
        expect(output).to include("Error Message")
        expect(output).to include("Test error")
      end
    end

    context "when job does not exist" do
      before do
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 999).and_return(nil)
        allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: 999).and_return(nil)
        allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: 999).and_return(nil)
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 999).and_return(nil)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.show(999) }

        expect(output).to include("Job 999 not found")
      end
    end
  end

  describe "#retry_job" do
    context "when SolidQueue is not available" do
      before do
        allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.retry_job(1) }

        expect(output).to include("SolidQueue is not available")
      end
    end

    context "when failed job exists" do
      let(:job) { double("FailedJob", id: 1, retry: true) }

      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(jobs_cli).to receive(:confirm).and_return(true)
      end

      it "retries the job" do
        expect(job).to receive(:retry)

        output = capture_stdout { jobs_cli.retry_job(1) }

        expect(output).to include("✓ Job 1 has been queued for retry")
      end
    end

    context "when user cancels" do
      let(:job) { double("FailedJob", id: 1, retry: true) }

      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(jobs_cli).to receive(:confirm).and_return(false)
      end

      it "does not retry the job" do
        expect(job).not_to receive(:retry)

        output = capture_stdout { jobs_cli.retry_job(1) }

        expect(output).to include("Retry cancelled")
      end
    end

    context "when failed job does not exist" do
      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 999).and_return(nil)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.retry_job(999) }

        expect(output).to include("Failed job 999 not found")
      end
    end
  end

  describe "#discard" do
    context "when SolidQueue is not available" do
      before do
        allow(SolidObserver::QueueStats).to receive(:solid_queue_available?).and_return(false)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.discard(1) }

        expect(output).to include("SolidQueue is not available")
      end
    end

    context "when failed job exists" do
      let(:job) { double("FailedJob", id: 1, discard: true) }

      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(jobs_cli).to receive(:confirm).and_return(true)
      end

      it "discards the job" do
        expect(job).to receive(:discard)

        output = capture_stdout { jobs_cli.discard(1) }

        expect(output).to include("✓ Job 1 has been discarded")
      end
    end

    context "when user cancels" do
      let(:job) { double("FailedJob", id: 1, discard: true) }

      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(job)
        allow(jobs_cli).to receive(:confirm).and_return(false)
      end

      it "does not discard the job" do
        expect(job).not_to receive(:discard)

        output = capture_stdout { jobs_cli.discard(1) }

        expect(output).to include("Discard cancelled")
      end
    end

    context "when failed job does not exist" do
      before do
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 999).and_return(nil)
      end

      it "displays error message" do
        output = capture_stdout { jobs_cli.discard(999) }

        expect(output).to include("Failed job 999 not found")
      end
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
