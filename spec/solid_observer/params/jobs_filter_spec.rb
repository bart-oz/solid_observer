# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Params::JobsFilter do
  describe ".from_params" do
    it "defaults status to ready" do
      filter = described_class.from_params(ActionController::Parameters.new({}))
      expect(filter.status).to eq("ready")
    end

    it "reads status from params" do
      filter = described_class.from_params(ActionController::Parameters.new(status: "failed"))
      expect(filter.status).to eq("failed")
    end

    it "reads queue_name from params" do
      filter = described_class.from_params(ActionController::Parameters.new(queue_name: "default"))
      expect(filter.queue_name).to eq("default")
    end

    it "reads job_class from params" do
      filter = described_class.from_params(ActionController::Parameters.new(job_class: "MyJob"))
      expect(filter.job_class).to eq("MyJob")
    end

    it "defaults page to 1" do
      filter = described_class.from_params(ActionController::Parameters.new({}))
      expect(filter.page).to eq(1)
    end

    it "converts page param to integer" do
      filter = described_class.from_params(ActionController::Parameters.new(page: "3"))
      expect(filter.page).to eq(3)
    end

    it "normalizes status case" do
      filter = described_class.from_params(ActionController::Parameters.new(status: "FAILED"))
      expect(filter.status).to eq("failed")
    end

    it "falls back to ready for unknown status" do
      filter = described_class.from_params(ActionController::Parameters.new(status: "unknown_status"))
      expect(filter.status).to eq("ready")
    end
  end
end
