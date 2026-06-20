# frozen_string_literal: true

require "spec_helper"
require "rake"

RSpec.describe "solid_observer cable rake tasks" do
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

  describe "solid_observer:cable:trim" do
    it "trims cable messages when available" do
      allow(SolidObserver::Services::CableOperations).to receive(:available?).and_return(true)
      allow(SolidObserver::Services::CableOperations).to receive(:trim).and_return(
        {message: "Expired/trimmable Solid Cable messages trimmed."}
      )

      expect {
        Rake::Task["solid_observer:cable:trim"].invoke
      }.to output("Expired/trimmable Solid Cable messages trimmed.\n").to_stdout

      expect(SolidObserver::Services::CableOperations).to have_received(:trim)
    end

    it "prints the unavailable message when cable controls cannot run" do
      allow(SolidObserver::Services::CableOperations).to receive(:available?).and_return(false)
      allow(SolidObserver::Services::CableOperations).to receive(:unavailable_message).and_return(
        "Cable controls are unavailable because Solid Cable support is disabled or not detected."
      )
      allow(SolidObserver::Services::CableOperations).to receive(:trim)

      expect {
        Rake::Task["solid_observer:cable:trim"].invoke
      }.to output("Cable controls are unavailable because Solid Cable support is disabled or not detected.\n").to_stdout

      expect(SolidObserver::Services::CableOperations).not_to have_received(:trim)
    end
  end
end
