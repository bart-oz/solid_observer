# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Events", type: :feature do
  before { SolidObserver.config.storage_mode = :persistence }
  after { SolidObserver::QueueEvent.delete_all }

  context "in persistence mode" do
    it "displays the Events heading" do
      visit "/solid_observer/events"
      expect(page).to have_css("h1", text: "Events")
    end

    it "shows filter dropdowns" do
      visit "/solid_observer/events"
      expect(page).to have_select("event_type")
      expect(page).to have_select("job_class")
      expect(page).to have_select("queue_name")
    end

    context "when no events exist" do
      it "displays the empty state message" do
        visit "/solid_observer/events"
        expect(page).to have_content("No events found")
      end
    end

    context "when events exist" do
      before do
        SolidObserver::QueueEvent.create!(
          event_type: "job_completed",
          job_class: "MyJob",
          queue_name: "default",
          recorded_at: Time.now
        )
      end

      it "displays the event in the table" do
        visit "/solid_observer/events"
        expect(page).to have_content("MyJob")
        expect(page).to have_content("default")
      end

      it "links to the event show page" do
        visit "/solid_observer/events"
        expect(page).to have_link("Job completed")
      end
    end
  end

  context "in realtime mode" do
    before { SolidObserver.config.storage_mode = :realtime }

    it "redirects to dashboard with an alert" do
      visit "/solid_observer/events"
      expect(page.current_path).to match(%r{/solid_observer/?$})
      expect(page).to have_content("not available in real-time mode")
    end
  end
end
