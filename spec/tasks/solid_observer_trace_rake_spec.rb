# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "solid_observer:trace rake task" do
  before(:all) do
    unless Rake::Task.task_defined?("solid_observer:trace")
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      load File.expand_path("../../lib/tasks/solid_observer.rake", __dir__)
    end
  end

  def reenable_all_tasks
    Rake::Task.tasks.each(&:reenable)
  end

  describe "task definition" do
    it "defines solid_observer:trace task" do
      expect(Rake::Task.task_defined?("solid_observer:trace")).to be true
    end

    it "accepts correlation_id and limit arguments" do
      task = Rake::Task["solid_observer:trace"]
      expect(task.arg_names).to eq([:correlation_id, :limit])
    end
  end

  describe "task execution" do
    before { reenable_all_tasks }

    it "exits with error when correlation_id is missing" do
      expect {
        Rake::Task["solid_observer:trace"].invoke
      }.to output(/Error: correlation_id required/).to_stdout.and raise_error(SystemExit)
    end

    it "invokes CLI::Trace with correlation_id and limit" do
      allow(SolidObserver::CLI::Trace).to receive(:call)

      Rake::Task["solid_observer:trace"].invoke("abc-123", "25")

      expect(SolidObserver::CLI::Trace).to have_received(:call).with(correlation_id: "abc-123", limit: "25")
    end

    it "invokes CLI::Trace with a nil limit when limit is not provided" do
      allow(SolidObserver::CLI::Trace).to receive(:call)

      Rake::Task["solid_observer:trace"].invoke("abc-123")

      expect(SolidObserver::CLI::Trace).to have_received(:call).with(correlation_id: "abc-123", limit: nil)
    end
  end
end
