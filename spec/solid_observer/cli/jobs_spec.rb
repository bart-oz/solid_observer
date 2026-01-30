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

  # Helper to create execution doubles with associated job
  def create_execution_double(id:, queue_name:, class_name:, created_at:, execution_class:)
    job = double("SolidQueueJob", queue_name: queue_name, class_name: class_name)
    execution = double("Execution",
      id: id,
      job: job,
      created_at: created_at,
      queue_name: queue_name) # Some executions have queue_name directly
    allow(execution).to receive(:try).with(:queue_name).and_return(queue_name)
    allow(execution).to receive(:is_a?) { |klass| klass == execution_class }
    execution
  end

  # Helper to setup scope chain
  def setup_scope_chain(execution_class, executions)
    scope = double("scope")
    allow(execution_class).to receive(:all).and_return(scope)
    allow(scope).to receive(:joins).and_return(scope)
    allow(scope).to receive(:where).and_return(scope)
    allow(scope).to receive(:order).and_return(scope)
    allow(scope).to receive(:limit).and_return(scope)
    allow(scope).to receive(:includes).and_return(scope)
    allow(scope).to receive(:to_a).and_return(executions)
    scope
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
      let(:execution1) do
        create_execution_double(
          id: 1,
          queue_name: "default",
          class_name: "TestJob",
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          execution_class: SolidQueue::ReadyExecution
        )
      end

      let(:execution2) do
        create_execution_double(
          id: 2,
          queue_name: "mailers",
          class_name: "MailerJob",
          created_at: Time.new(2026, 1, 21, 11, 0, 0),
          execution_class: SolidQueue::ReadyExecution
        )
      end

      context "with no filters" do
        before do
          setup_scope_chain(SolidQueue::ReadyExecution, [execution1, execution2])
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
        let(:failed_execution) do
          create_execution_double(
            id: 3,
            queue_name: "default",
            class_name: "FailingJob",
            created_at: Time.new(2026, 1, 21, 12, 0, 0),
            execution_class: SolidQueue::FailedExecution
          )
        end

        before do
          setup_scope_chain(SolidQueue::FailedExecution, [failed_execution])
        end

        it "fetches jobs with specified status" do
          output = capture_stdout { jobs_cli.list(status: "failed") }

          expect(output).to include("Failed")
          expect(output).to include("FailingJob")
        end
      end

      context "with queue filter" do
        before do
          setup_scope_chain(SolidQueue::ReadyExecution, [execution2])
        end

        it "fetches jobs from specified queue" do
          output = capture_stdout { jobs_cli.list(queue: "mailers") }

          expect(output).to include("mailers")
          expect(output).to include("MailerJob")
        end
      end

      context "with job_class filter" do
        before do
          setup_scope_chain(SolidQueue::ReadyExecution, [execution1])
        end

        it "fetches jobs of specified class" do
          output = capture_stdout { jobs_cli.list(job_class: "TestJob") }

          expect(output).to include("TestJob")
        end
      end

      context "with limit" do
        before do
          setup_scope_chain(SolidQueue::ReadyExecution, [execution1])
        end

        it "limits number of jobs returned" do
          output = capture_stdout { jobs_cli.list(limit: 5) }

          expect(output).to include("TestJob")
        end
      end

      context "when no jobs found" do
        before do
          setup_scope_chain(SolidQueue::ReadyExecution, [])
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
      let(:job_record) do
        double("SolidQueue::Job",
          id: 100,
          queue_name: "default",
          class_name: "TestJob",
          priority: 0)
      end
      let(:execution) do
        double("Execution",
          id: 1,
          job: job_record,
          created_at: Time.new(2026, 1, 21, 10, 0, 0))
      end

      before do
        allow(execution).to receive(:try).with(:queue_name).and_return(nil)
        allow(execution).to receive(:try).with(:scheduled_at).and_return(nil)
        allow(execution).to receive(:try).with(:process_id).and_return(nil)
        allow(execution).to receive(:try).with(:priority).and_return(nil)
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(execution)
        allow(execution).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(true)
        allow(execution).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
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
      let(:job_record) do
        double("SolidQueue::Job",
          id: 100,
          queue_name: "default",
          class_name: "TestJob",
          priority: 0)
      end
      let(:execution) do
        double("Execution",
          id: 1,
          job: job_record,
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          scheduled_at: Time.new(2026, 1, 21, 12, 0, 0))
      end

      before do
        allow(execution).to receive(:try).with(:queue_name).and_return(nil)
        allow(execution).to receive(:try).with(:scheduled_at).and_return(Time.new(2026, 1, 21, 12, 0, 0))
        allow(execution).to receive(:try).with(:process_id).and_return(nil)
        allow(execution).to receive(:try).with(:priority).and_return(nil)
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: 1).and_return(execution)
        allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(execution).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(true)
        allow(execution).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(false)
      end

      it "displays scheduled_at field" do
        output = capture_stdout { jobs_cli.show(1) }

        expect(output).to include("Scheduled At")
        expect(output).to include("2026-01-21 12:00:00")
      end
    end

    context "when job is failed" do
      let(:error) { double("Error", exception_class: "StandardError", message: "Test error") }
      let(:job_record) do
        double("SolidQueue::Job",
          id: 100,
          queue_name: "default",
          class_name: "TestJob",
          priority: 0)
      end
      let(:execution) do
        double("Execution",
          id: 1,
          job: job_record,
          created_at: Time.new(2026, 1, 21, 10, 0, 0),
          error: error)
      end

      before do
        allow(execution).to receive(:try).with(:queue_name).and_return(nil)
        allow(execution).to receive(:try).with(:scheduled_at).and_return(nil)
        allow(execution).to receive(:try).with(:process_id).and_return(nil)
        allow(execution).to receive(:try).with(:priority).and_return(nil)
        allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::ClaimedExecution).to receive(:find_by).with(id: 1).and_return(nil)
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: 1).and_return(execution)
        allow(execution).to receive(:is_a?).with(SolidQueue::ReadyExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::ScheduledExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::ClaimedExecution).and_return(false)
        allow(execution).to receive(:is_a?).with(SolidQueue::FailedExecution).and_return(true)
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
