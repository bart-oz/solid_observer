# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Dashboard", type: :feature do
  before { SolidObserver.config.storage_mode = :persistence }

  it "displays the Dashboard heading" do
    visit "/solid_observer"
    expect(page).to have_css("h1", text: "Dashboard")
  end

  it "shows the SolidObserver logo in the sidebar" do
    visit "/solid_observer"
    expect(page).to have_content("SolidObserver")
  end

  it "shows Dashboard and Jobs navigation links" do
    visit "/solid_observer"
    expect(page).to have_link("Dashboard")
    expect(page).to have_link("Jobs")
  end

  context "in persistence mode" do
    before do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(
        ready: 10,
        scheduled: 5,
        claimed: 2,
        failed: 1,
        workers: 3,
        queues: {},
        available: true,
        performed_last_hour: 1200,
        failed_last_24h: 9,
        enqueue_rate_per_min: 4.6
      )
      allow(SolidObserver::QueueEvent).to receive(:recent).and_return([])
      allow(SolidObserver::QueueEvent).to receive(:recent_failures).and_return([])
    end

    it "shows Events and Storage navigation links" do
      visit "/solid_observer"
      expect(page).to have_link("Events")
      expect(page).to have_link("Storage")
    end

    it "shows Persistence mode indicator" do
      visit "/solid_observer"
      expect(page).to have_content("Persistence")
    end

    it "shows conceptual hint and throughput cards" do
      visit "/solid_observer"

      expect(page).to have_link("Events tab")
      expect(page).to have_content("Jobs tab")
      expect(page).to have_content("Performed")
      expect(page).to have_content("last hour")
      expect(page).to have_content("Failed")
      expect(page).to have_content("last 24h")
      expect(page).to have_content("Enqueue rate")
      expect(page).to have_content("4.6 jobs/min")
    end

    it "shows reassurance when there are no recent failures" do
      visit "/solid_observer"

      expect(page).to have_content("Recent Failures")
      expect(page).to have_content("No recent failures.")
    end
  end

  context "in realtime mode" do
    before { SolidObserver.config.storage_mode = :realtime }

    it "does not show Events and Storage navigation links" do
      visit "/solid_observer"
      expect(page).not_to have_link("Events")
      expect(page).not_to have_link("Storage")
    end

    it "shows Real-time mode indicator" do
      visit "/solid_observer"
      expect(page).to have_content("Real-time")
    end

    it "does not show persistence-only hint and throughput cards" do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(
        ready: 1,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 1,
        queues: {},
        available: true
      )

      visit "/solid_observer"

      expect(page).not_to have_content("Jobs tab")
      expect(page).not_to have_content("Performed")
      expect(page).not_to have_content("Enqueue rate")
    end
  end

  context "when UI is disabled" do
    before { SolidObserver.config.ui_enabled = false }

    it "returns a 404 response" do
      visit "/solid_observer"
      expect(page).to have_content("Not Found")
    end
  end
end
