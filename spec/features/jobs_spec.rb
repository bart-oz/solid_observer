# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Jobs", type: :feature do
  context "when SolidQueue is not available" do
    it "redirects to dashboard with an alert" do
      visit "/solid_observer/jobs"
      expect(page.current_path).to match(%r{/solid_observer/?$})
    end

    it "displays the SolidQueue unavailable alert" do
      visit "/solid_observer/jobs"
      expect(page).to have_content("SolidQueue is not available")
    end
  end
end
