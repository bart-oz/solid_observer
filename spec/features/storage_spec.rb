# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Storage", type: :feature do
  before { SolidObserver.config.storage_mode = :persistence }
  after { SolidObserver::StorageInfo.delete_all }

  context "in persistence mode" do
    it "displays the Storage heading" do
      visit "/solid_observer/storage"
      expect(page).to have_css("h1", text: "Storage")
    end

    context "when no storage data exists" do
      it "displays component health from live inspection" do
        visit "/solid_observer/storage"
        expect(page).to have_content("Component health")
        expect(page).to have_content("Queue observer")
      end
    end

    context "when storage data exists" do
      before do
        SolidObserver::StorageInfo.create!(
          component: "queue_observer",
          db_size_bytes: 2_048,
          event_count: 42,
          recorded_at: Time.now
        )
      end

      it "displays component health card" do
        visit "/solid_observer/storage"
        expect(page).to have_css(".so-dashboard")
        expect(page).to have_content("Component health")
        expect(page).to have_content("Queue observer")
        expect(page).to have_content("2.0 KB")
      end

      it "displays records value" do
        visit "/solid_observer/storage"
        expect(page).to have_content("42 observer events")
      end

      it "displays the recent snapshots table" do
        visit "/solid_observer/storage"
        expect(page).to have_content("Recent Snapshots")
        expect(page).to have_content("Component")
      end
    end
  end

  context "in realtime mode" do
    before { SolidObserver.config.storage_mode = :realtime }

    it "redirects to dashboard with an alert" do
      visit "/solid_observer/storage"
      expect(page.current_path).to match(%r{/solid_observer/?$})
      expect(page).to have_content("not available in real-time mode")
    end
  end
end
