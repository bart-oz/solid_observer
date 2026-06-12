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

    describe "solid_observer:install:migrations" do
      before do
        install_migrations_service = Class.new do
          def self.call
          end
        end

        stub_const("SolidObserver::Services::InstallMigrations", install_migrations_service)
        allow(SolidObserver::Services::InstallMigrations).to receive(:call)
      end

      it "prints singular copy output when one migration is copied" do
        allow(SolidObserver::Services::InstallMigrations).to receive(:call).and_return(
          {destination: "db/solid_observer_migrate", copied: ["20260115000001"]}
        )

        expect {
          Rake::Task["solid_observer:install:migrations"].invoke
        }.to output("Copied 1 SolidObserver migration to db/solid_observer_migrate/\n").to_stdout

        expect(SolidObserver::Services::InstallMigrations).to have_received(:call)
      end

      it "prints plural copy output when multiple migrations are copied" do
        allow(SolidObserver::Services::InstallMigrations).to receive(:call).and_return(
          {destination: "db/solid_observer_migrate", copied: %w[20260115000001 20260115000002]}
        )

        expect {
          Rake::Task["solid_observer:install:migrations"].invoke
        }.to output("Copied 2 SolidObserver migrations to db/solid_observer_migrate/\n").to_stdout
      end

      it "prints no-op output when all migrations are already present" do
        allow(SolidObserver::Services::InstallMigrations).to receive(:call).and_return(
          {destination: "db/solid_observer_migrate", copied: []}
        )

        expect {
          Rake::Task["solid_observer:install:migrations"].invoke
        }.to output(
          "No new SolidObserver migrations to copy (all already present in db/solid_observer_migrate/)\n"
        ).to_stdout
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
      let(:queue_buffer) { instance_double(SolidObserver::QueueEventBuffer) }
      let(:cache_event_buffer) { instance_double(SolidObserver::CacheEventBuffer) }
      let(:cache_metric_buffer) { instance_double(SolidObserver::CacheMetricBuffer) }

      before do
        allow(SolidObserver::QueueEventBuffer).to receive(:instance).and_return(queue_buffer)
        allow(SolidObserver::CacheEventBuffer).to receive(:instance).and_return(cache_event_buffer)
        allow(SolidObserver::CacheMetricBuffer).to receive(:instance).and_return(cache_metric_buffer)
      end

      it "flushes queue event, cache event, and cache metric buffers when present" do
        allow(queue_buffer).to receive(:size).and_return(5)
        allow(cache_event_buffer).to receive(:size).and_return(2)
        allow(cache_metric_buffer).to receive(:size).and_return(3)
        allow(queue_buffer).to receive(:flush!)
        allow(cache_event_buffer).to receive(:flush!)
        allow(cache_metric_buffer).to receive(:flush!)

        expect {
          Rake::Task["solid_observer:buffer:flush"].invoke
        }.to output(/Flushing 5 queue events.*Flushing 2 cache events.*Flushing 3 cache metric buckets.*Buffers flushed successfully/m).to_stdout

        expect(queue_buffer).to have_received(:flush!)
        expect(cache_event_buffer).to have_received(:flush!)
        expect(cache_metric_buffer).to have_received(:flush!)
      end

      it "reports empty buffers when no buffers have data" do
        allow(queue_buffer).to receive(:size).and_return(0)
        allow(cache_event_buffer).to receive(:size).and_return(0)
        allow(cache_metric_buffer).to receive(:size).and_return(0)

        expect {
          reenable_all_tasks
          Rake::Task["solid_observer:buffer:flush"].invoke
        }.to output(/Buffers are empty, nothing to flush/).to_stdout
      end
    end

    describe "solid_observer:buffer:clear" do
      let(:queue_buffer) { instance_double(SolidObserver::QueueEventBuffer) }
      let(:cache_event_buffer) { instance_double(SolidObserver::CacheEventBuffer) }
      let(:cache_metric_buffer) { instance_double(SolidObserver::CacheMetricBuffer) }

      before do
        allow(SolidObserver::QueueEventBuffer).to receive(:instance).and_return(queue_buffer)
        allow(SolidObserver::CacheEventBuffer).to receive(:instance).and_return(cache_event_buffer)
        allow(SolidObserver::CacheMetricBuffer).to receive(:instance).and_return(cache_metric_buffer)
      end

      it "clears queue event, cache event, and cache metric buffers when present" do
        allow(queue_buffer).to receive(:size).and_return(3)
        allow(cache_event_buffer).to receive(:size).and_return(2)
        allow(cache_metric_buffer).to receive(:size).and_return(1)
        allow(queue_buffer).to receive(:clear)
        allow(cache_event_buffer).to receive(:clear)
        allow(cache_metric_buffer).to receive(:clear)

        expect {
          Rake::Task["solid_observer:buffer:clear"].invoke
        }.to output(/Cleared 3 queue events.*Cleared 2 cache events.*Cleared 1 cache metric buckets/m).to_stdout

        expect(queue_buffer).to have_received(:clear)
        expect(cache_event_buffer).to have_received(:clear)
        expect(cache_metric_buffer).to have_received(:clear)
      end

      it "reports already empty when all buffers are empty" do
        allow(queue_buffer).to receive(:size).and_return(0)
        allow(cache_event_buffer).to receive(:size).and_return(0)
        allow(cache_metric_buffer).to receive(:size).and_return(0)

        expect {
          reenable_all_tasks
          Rake::Task["solid_observer:buffer:clear"].invoke
        }.to output(/Buffers are already empty/).to_stdout
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
        allow(connection).to receive(:adapter_name).and_return("SQLite")
      end

      it "purges data when user confirms with y" do
        allow($stdin).to receive(:gets).and_return("y\n")

        expect {
          Rake::Task["solid_observer:storage:purge"].invoke
        }.to output(/Purged 100 events and 10 storage snapshots/m).to_stdout

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
