# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Params::EventsFilter do
  describe ".from_params" do
    it "extracts event_type from params" do
      filter = described_class.from_params(ActionController::Parameters.new(event_type: "job_failed"))
      expect(filter.event_type).to eq("job_failed")
    end

    it "extracts job_class from params" do
      filter = described_class.from_params(ActionController::Parameters.new(job_class: "MyJob"))
      expect(filter.job_class).to eq("MyJob")
    end

    it "extracts queue_name from params" do
      filter = described_class.from_params(ActionController::Parameters.new(queue_name: "default"))
      expect(filter.queue_name).to eq("default")
    end

    it "defaults page to 1 when not given" do
      filter = described_class.from_params(ActionController::Parameters.new({}))
      expect(filter.page).to eq(1)
    end

    it "converts page to integer" do
      filter = described_class.from_params(ActionController::Parameters.new(page: "4"))
      expect(filter.page).to eq(4)
    end

    it "parses from date" do
      filter = described_class.from_params(ActionController::Parameters.new(from: "2026-01-01"))
      expect(filter.from).to eq(Date.new(2026, 1, 1))
    end

    it "parses to date" do
      filter = described_class.from_params(ActionController::Parameters.new(to: "2026-01-31"))
      expect(filter.to).to eq(Date.new(2026, 1, 31))
    end

    it "returns nil for blank date string" do
      filter = described_class.from_params(ActionController::Parameters.new(from: ""))
      expect(filter.from).to be_nil
    end

    it "returns nil for invalid date" do
      filter = described_class.from_params(ActionController::Parameters.new(from: "not-a-date"))
      expect(filter.from).to be_nil
    end
  end
end
