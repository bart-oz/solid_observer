# frozen_string_literal: true

require "spec_helper"
require "action_view"
require_relative "../../app/helpers/solid_observer/application_helper"

RSpec.describe SolidObserver::ApplicationHelper do
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  include described_class

  describe "#format_duration" do
    it "returns '0ms' for nil" do
      expect(format_duration(nil)).to eq("0ms")
    end

    it "returns '0ms' for zero" do
      expect(format_duration(0)).to eq("0ms")
    end

    it "formats 0.011 seconds as 11ms" do
      expect(format_duration(0.011)).to eq("11ms")
    end

    it "formats 2.5 seconds as seconds output" do
      expect(format_duration(2.5)).to eq("2.5s")
    end

    it "formats exactly 1 second" do
      expect(format_duration(1.0)).to eq("1.0s")
    end
  end

  describe "#duration_with_semantic" do
    it "wraps duration in an abbr tag with perform text for job_completed" do
      result = duration_with_semantic(0.011, "job_completed")

      expect(result).to include("<abbr")
      expect(result).to include("11ms")
      expect(result).to include("Time spent performing the job")
    end

    it "uses enqueue-specific text for job_enqueued" do
      result = duration_with_semantic(0.005, "job_enqueued")
      expect(result).to include("ActiveJob enqueue call")
    end

    it "uses failed-specific text for job_failed" do
      result = duration_with_semantic(1.5, "job_failed")
      expect(result).to include("before the exception was raised")
    end

    it "uses discarded-specific text for job_discarded" do
      result = duration_with_semantic(0.2, "job_discarded")
      expect(result).to include("discard decision was made")
    end

    it "renders an em-dash for nil duration" do
      result = duration_with_semantic(nil, "job_completed")

      expect(result).to include("—")
      expect(result).to include("so-text-muted")
    end

    it "raises KeyError for unknown event type" do
      expect {
        duration_with_semantic(0.011, "job_unknown")
      }.to raise_error(KeyError)
    end
  end

  describe "#status_badge" do
    it "uses success for completed" do
      expect(status_badge(:completed)).to include("so-badge--success")
    end

    it "uses success for ready" do
      expect(status_badge(:ready)).to include("so-badge--success")
    end

    it "uses danger for failed" do
      expect(status_badge(:failed)).to include("so-badge--danger")
    end

    it "uses danger for retry_stopped" do
      expect(status_badge(:retry_stopped)).to include("so-badge--danger")
    end

    it "uses warning for scheduled" do
      expect(status_badge(:scheduled)).to include("so-badge--warning")
    end

    it "uses warning for claimed" do
      expect(status_badge(:claimed)).to include("so-badge--warning")
    end

    it "uses info for enqueued" do
      expect(status_badge(:enqueued)).to include("so-badge--info")
    end

    it "uses info for discarded" do
      expect(status_badge(:discarded)).to include("so-badge--info")
    end

    it "uses default for unknown status" do
      expect(status_badge(:unknown)).to include("so-badge--default")
    end

    it "humanizes the status text" do
      expect(status_badge(:retry_stopped)).to include("Retry stopped")
    end
  end

  describe "#mode_badge" do
    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }
      after { SolidObserver.config.storage_mode = :persistence }

      it "renders info badge" do
        expect(mode_badge).to include("so-badge--info")
      end

      it "shows Persistence" do
        expect(mode_badge).to include("Persistence")
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }
      after { SolidObserver.config.storage_mode = :persistence }

      it "renders warning badge" do
        expect(mode_badge).to include("so-badge--warning")
      end

      it "shows Realtime" do
        expect(mode_badge).to include("Realtime")
      end
    end
  end
end
