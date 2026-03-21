# frozen_string_literal: true

require "spec_helper"
require "action_view"
require_relative "../../app/helpers/solid_observer/application_helper"

RSpec.describe SolidObserver::ApplicationHelper do
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  include described_class

  describe "#format_bytes" do
    it "returns '0 B' for nil" do
      expect(format_bytes(nil)).to eq("0 B")
    end

    it "returns '0 B' for zero" do
      expect(format_bytes(0)).to eq("0 B")
    end

    it "returns '0 B' for values under 1 KB" do
      expect(format_bytes(500)).to eq("0 B")
    end

    it "formats KB" do
      expect(format_bytes(2_048)).to eq("2.0 KB")
    end

    it "formats MB" do
      expect(format_bytes(5 * 1_048_576)).to eq("5.0 MB")
    end

    it "formats GB" do
      expect(format_bytes(2 * 1_073_741_824)).to eq("2.0 GB")
    end
  end

  describe "#format_duration" do
    it "returns '0ms' for nil" do
      expect(format_duration(nil)).to eq("0ms")
    end

    it "returns '0ms' for zero" do
      expect(format_duration(0)).to eq("0ms")
    end

    it "formats sub-second as ms" do
      expect(format_duration(0.003)).to eq("3ms")
    end

    it "formats seconds" do
      expect(format_duration(1.2)).to eq("1.2s")
    end

    it "formats exactly 1 second" do
      expect(format_duration(1.0)).to eq("1.0s")
    end
  end

  describe "#format_number" do
    it "returns '0' for nil" do
      expect(format_number(nil)).to eq("0")
    end

    it "formats large numbers with commas" do
      expect(format_number(1_234_567)).to eq("1,234,567")
    end

    it "returns small numbers unchanged" do
      expect(format_number(42)).to eq("42")
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
