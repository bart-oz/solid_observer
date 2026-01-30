# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "solid_observer rake tasks" do
  before(:all) do
    Rake.application = Rake::Application.new
    Rake.application.rake_require("solid_observer", [File.expand_path("../../lib/tasks", __dir__)])
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
end
