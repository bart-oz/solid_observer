# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "solid_observer cache rake tasks" do
  before(:all) do
    unless Rake::Task.task_defined?("solid_observer:status")
      Rake.application = Rake::Application.new
      Rake::Task.define_task(:environment)
      load File.expand_path("../../lib/tasks/solid_observer.rake", __dir__)
    end
  end

  before do
    Rake::Task.tasks.each(&:reenable)
  end

  describe "solid_observer:cache:clear" do
    it "clears cache when available and confirmed" do
      allow(SolidObserver::Services::CacheOperations).to receive(:available?).and_return(true)
      allow(SolidObserver::Services::CacheOperations).to receive(:message).with(:clear, :confirmation).and_return("Confirm cache clear")
      allow(SolidObserver::Services::CacheOperations).to receive(:clear).and_return({message: "Cache cleared successfully."})
      allow($stdin).to receive(:gets).and_return("y\n")

      expect {
        Rake::Task["solid_observer:cache:clear"].invoke
      }.to output(/Confirm cache clear \(y\/N\) Cache cleared successfully\./).to_stdout

      expect(SolidObserver::Services::CacheOperations).to have_received(:clear)
    end

    it "aborts cache clear when the user does not confirm" do
      allow(SolidObserver::Services::CacheOperations).to receive(:available?).and_return(true)
      allow(SolidObserver::Services::CacheOperations).to receive(:message).with(:clear, :confirmation).and_return("Confirm cache clear")
      allow(SolidObserver::Services::CacheOperations).to receive(:clear)
      allow($stdin).to receive(:gets).and_return("n\n")

      expect {
        Rake::Task["solid_observer:cache:clear"].invoke
      }.to output(/Confirm cache clear \(y\/N\) Aborted/).to_stdout

      expect(SolidObserver::Services::CacheOperations).not_to have_received(:clear)
    end

    it "prints the unavailable message when cache controls cannot run" do
      allow(SolidObserver::Services::CacheOperations).to receive(:available?).and_return(false)
      allow(SolidObserver::Services::CacheOperations).to receive(:unavailable_message).and_return("Cache controls unavailable")

      expect {
        Rake::Task["solid_observer:cache:clear"].invoke
      }.to output("Cache controls unavailable\n").to_stdout
    end
  end

  describe "solid_observer:cache:prune" do
    it "prunes cache when available" do
      allow(SolidObserver::Services::CacheOperations).to receive(:available?).and_return(true)
      allow(SolidObserver::Services::CacheOperations).to receive(:prune).and_return({message: "Expired cache entries pruned successfully."})

      expect {
        Rake::Task["solid_observer:cache:prune"].invoke
      }.to output("Expired cache entries pruned successfully.\n").to_stdout

      expect(SolidObserver::Services::CacheOperations).to have_received(:prune)
    end

    it "prints the unavailable message when pruning cannot run" do
      allow(SolidObserver::Services::CacheOperations).to receive(:available?).and_return(false)
      allow(SolidObserver::Services::CacheOperations).to receive(:unavailable_message).and_return("Cache controls unavailable")
      allow(SolidObserver::Services::CacheOperations).to receive(:prune)

      expect {
        Rake::Task["solid_observer:cache:prune"].invoke
      }.to output("Cache controls unavailable\n").to_stdout

      expect(SolidObserver::Services::CacheOperations).not_to have_received(:prune)
    end
  end
end
