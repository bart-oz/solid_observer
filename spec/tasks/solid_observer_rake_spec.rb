# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "solid_observer rake tasks" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake::Task.define_task(:environment)
    Rake.application.rake_require("solid_observer", [File.expand_path("../../lib/tasks", __dir__)])
  end

  def reenable_all_tasks
    Rake::Task.tasks.each(&:reenable)
  end

  describe "task definitions" do
    it "defines solid_observer:status task" do
      expect(Rake::Task.task_defined?("solid_observer:status")).to be true
    end

    it "defines solid_observer:storage task" do
      expect(Rake::Task.task_defined?("solid_observer:storage")).to be true
    end

    it "defines solid_observer:jobs:list task" do
      expect(Rake::Task.task_defined?("solid_observer:jobs:list")).to be true
    end

    it "defines solid_observer:jobs:show task" do
      expect(Rake::Task.task_defined?("solid_observer:jobs:show")).to be true
    end

    it "defines solid_observer:jobs:retry task" do
      expect(Rake::Task.task_defined?("solid_observer:jobs:retry")).to be true
    end

    it "defines solid_observer:jobs:discard task" do
      expect(Rake::Task.task_defined?("solid_observer:jobs:discard")).to be true
    end

    it "defines solid_observer:install:migrations task" do
      expect(Rake::Task.task_defined?("solid_observer:install:migrations")).to be true
    end

    it "defines solid_observer:db:create task" do
      expect(Rake::Task.task_defined?("solid_observer:db:create")).to be true
    end

    it "defines solid_observer:db:migrate task" do
      expect(Rake::Task.task_defined?("solid_observer:db:migrate")).to be true
    end

    it "defines solid_observer:buffer:flush task" do
      expect(Rake::Task.task_defined?("solid_observer:buffer:flush")).to be true
    end

    it "defines solid_observer:buffer:clear task" do
      expect(Rake::Task.task_defined?("solid_observer:buffer:clear")).to be true
    end

    it "defines solid_observer:storage:cleanup task" do
      expect(Rake::Task.task_defined?("solid_observer:storage:cleanup")).to be true
    end

    it "defines solid_observer:storage:purge task" do
      expect(Rake::Task.task_defined?("solid_observer:storage:purge")).to be true
    end
  end

  describe "task arguments" do
    it "solid_observer:jobs:list accepts status, queue, job_class, limit arguments" do
      task = Rake::Task["solid_observer:jobs:list"]
      expect(task.arg_names).to eq([:status, :queue, :job_class, :limit])
    end

    it "solid_observer:jobs:show accepts job_id argument" do
      task = Rake::Task["solid_observer:jobs:show"]
      expect(task.arg_names).to eq([:job_id])
    end

    it "solid_observer:jobs:retry accepts job_id argument" do
      task = Rake::Task["solid_observer:jobs:retry"]
      expect(task.arg_names).to eq([:job_id])
    end

    it "solid_observer:jobs:discard accepts job_id argument" do
      task = Rake::Task["solid_observer:jobs:discard"]
      expect(task.arg_names).to eq([:job_id])
    end
  end

  describe "task execution" do
    before do
      reenable_all_tasks
    end

    describe "solid_observer:status" do
      it "invokes CLI::Status.call" do
        allow(SolidObserver::CLI::Status).to receive(:call)
        Rake::Task["solid_observer:status"].invoke
        expect(SolidObserver::CLI::Status).to have_received(:call)
      end
    end

    describe "solid_observer:storage" do
      it "invokes CLI::Storage.call" do
        allow(SolidObserver::CLI::Storage).to receive(:call)
        Rake::Task["solid_observer:storage"].invoke
        expect(SolidObserver::CLI::Storage).to have_received(:call)
      end
    end

    describe "solid_observer:jobs:list" do
      it "invokes CLI::Jobs#list with arguments" do
        jobs_instance = instance_double(SolidObserver::CLI::Jobs)
        allow(SolidObserver::CLI::Jobs).to receive(:new).and_return(jobs_instance)
        allow(jobs_instance).to receive(:list)

        Rake::Task["solid_observer:jobs:list"].invoke("ready", "default", "TestJob", "10")

        expect(jobs_instance).to have_received(:list).with(
          status: "ready",
          queue: "default",
          job_class: "TestJob",
          limit: "10"
        )
      end

      it "uses default limit of 20 when not provided" do
        jobs_instance = instance_double(SolidObserver::CLI::Jobs)
        allow(SolidObserver::CLI::Jobs).to receive(:new).and_return(jobs_instance)
        allow(jobs_instance).to receive(:list)

        reenable_all_tasks
        Rake::Task["solid_observer:jobs:list"].invoke

        expect(jobs_instance).to have_received(:list).with(
          status: nil,
          queue: nil,
          job_class: nil,
          limit: 20
        )
      end
    end

    describe "solid_observer:jobs:show" do
      it "invokes CLI::Jobs#show with job_id" do
        jobs_instance = instance_double(SolidObserver::CLI::Jobs)
        allow(SolidObserver::CLI::Jobs).to receive(:new).and_return(jobs_instance)
        allow(jobs_instance).to receive(:show)

        Rake::Task["solid_observer:jobs:show"].invoke("123")

        expect(jobs_instance).to have_received(:show).with("123")
      end

      it "exits with error when job_id is nil" do
        expect {
          Rake::Task["solid_observer:jobs:show"].invoke
        }.to output(/Error: Job ID required/).to_stdout.and raise_error(SystemExit)
      end
    end

    describe "solid_observer:jobs:retry" do
      it "invokes CLI::Jobs#retry_job with job_id" do
        jobs_instance = instance_double(SolidObserver::CLI::Jobs)
        allow(SolidObserver::CLI::Jobs).to receive(:new).and_return(jobs_instance)
        allow(jobs_instance).to receive(:retry_job)

        Rake::Task["solid_observer:jobs:retry"].invoke("456")

        expect(jobs_instance).to have_received(:retry_job).with("456")
      end

      it "exits with error when job_id is nil" do
        expect {
          Rake::Task["solid_observer:jobs:retry"].invoke
        }.to output(/Error: Job ID required/).to_stdout.and raise_error(SystemExit)
      end
    end

    describe "solid_observer:jobs:discard" do
      it "invokes CLI::Jobs#discard with job_id" do
        jobs_instance = instance_double(SolidObserver::CLI::Jobs)
        allow(SolidObserver::CLI::Jobs).to receive(:new).and_return(jobs_instance)
        allow(jobs_instance).to receive(:discard)

        Rake::Task["solid_observer:jobs:discard"].invoke("789")

        expect(jobs_instance).to have_received(:discard).with("789")
      end

      it "exits with error when job_id is nil" do
        expect {
          Rake::Task["solid_observer:jobs:discard"].invoke
        }.to output(/Error: Job ID required/).to_stdout.and raise_error(SystemExit)
      end
    end

    describe "solid_observer:buffer:flush" do
      let(:buffer) { instance_double(SolidObserver::QueueEventBuffer) }

      before do
        allow(SolidObserver::QueueEventBuffer).to receive(:instance).and_return(buffer)
      end

      it "flushes buffer when it has events" do
        allow(buffer).to receive(:size).and_return(5)
        allow(buffer).to receive(:flush!)

        expect {
          Rake::Task["solid_observer:buffer:flush"].invoke
        }.to output(/Flushing 5 events.*Buffer flushed successfully/m).to_stdout

        expect(buffer).to have_received(:flush!)
      end

      it "reports empty buffer when no events" do
        allow(buffer).to receive(:size).and_return(0)

        expect {
          reenable_all_tasks
          Rake::Task["solid_observer:buffer:flush"].invoke
        }.to output(/Buffer is empty, nothing to flush/).to_stdout
      end
    end

    describe "solid_observer:buffer:clear" do
      let(:buffer) { instance_double(SolidObserver::QueueEventBuffer) }

      before do
        allow(SolidObserver::QueueEventBuffer).to receive(:instance).and_return(buffer)
      end

      it "clears buffer when it has events" do
        allow(buffer).to receive(:size).and_return(3)
        allow(buffer).to receive(:clear)

        expect {
          Rake::Task["solid_observer:buffer:clear"].invoke
        }.to output(/Cleared 3 events from buffer/).to_stdout

        expect(buffer).to have_received(:clear)
      end

      it "reports already empty when no events" do
        allow(buffer).to receive(:size).and_return(0)

        expect {
          reenable_all_tasks
          Rake::Task["solid_observer:buffer:clear"].invoke
        }.to output(/Buffer is already empty/).to_stdout
      end
    end

    describe "solid_observer:storage:cleanup" do
      it "runs cleanup and reports deleted count" do
        allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)
        allow(SolidObserver::Services::CleanupStorage).to receive(:call).and_return(42)

        expect {
          Rake::Task["solid_observer:storage:cleanup"].invoke
        }.to output(/Running storage cleanup.*Cleanup complete: 42 old events deleted/m).to_stdout

        expect(SolidObserver::Services::CleanupStorage).to have_received(:call)
      end
    end

    describe "solid_observer:storage:purge" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        allow(SolidObserver::QueueEvent).to receive(:delete_all)
        allow(SolidObserver::StorageInfo).to receive(:count).and_return(10)
        allow(SolidObserver::StorageInfo).to receive(:delete_all)

        connection = instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter)
        allow(SolidObserver::QueueEvent).to receive(:connection).and_return(connection)
        allow(connection).to receive(:execute)
      end

      it "purges data when user confirms with y" do
        allow($stdin).to receive(:gets).and_return("y\n")

        expect {
          Rake::Task["solid_observer:storage:purge"].invoke
        }.to output(/Purged 100 events and 10 storage snapshots.*Database vacuumed/m).to_stdout

        expect(SolidObserver::QueueEvent).to have_received(:delete_all)
        expect(SolidObserver::StorageInfo).to have_received(:delete_all)
      end

      it "aborts when user does not confirm" do
        allow($stdin).to receive(:gets).and_return("n\n")

        expect {
          reenable_all_tasks
          Rake::Task["solid_observer:storage:purge"].invoke
        }.to output(/Aborted/).to_stdout

        expect(SolidObserver::QueueEvent).not_to have_received(:delete_all)
      end
    end
  end
end
