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
    it "shows Events and Storage navigation links" do
      visit "/solid_observer"
      expect(page).to have_link("Events")
      expect(page).to have_link("Storage")
    end

    it "shows Persistence mode indicator" do
      visit "/solid_observer"
      expect(page).to have_content("Persistence")
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
  end

  context "when UI is disabled" do
    before { SolidObserver.config.ui_enabled = false }

    it "returns a 404 response" do
      visit "/solid_observer"
      expect(page).to have_content("Not Found")
    end
  end
end
