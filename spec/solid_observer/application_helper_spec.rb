# frozen_string_literal: true

require "spec_helper"
require "action_view"
require_relative "../../app/helpers/solid_observer/application_helper"

RSpec.describe SolidObserver::ApplicationHelper do
  include ActionView::Helpers::TagHelper
  include ActionView::Helpers::OutputSafetyHelper
  include ActionView::Helpers::TextHelper
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

  describe "#turbo_frame_tag" do
    it "renders a turbo frame with block content" do
      result = turbo_frame_tag("so_right_now") { "Right now content" }

      expect(result).to include("<turbo-frame")
      expect(result).to include('id="so_right_now"')
      expect(result).to include("Right now content")
      expect(result).to include("</turbo-frame>")
    end

    it "renders a turbo frame with src in non-block form" do
      result = turbo_frame_tag("so_lazy", src: "/solid_observer/scoped")

      expect(result).to include("<turbo-frame")
      expect(result).to include('id="so_lazy"')
      expect(result).to include('src="/solid_observer/scoped"')
      expect(result).to include("</turbo-frame>")
    end
  end

  describe "#stability_state" do
    it "returns :stable when both windows are zero" do
      expect(stability_state(failed_last_hour: 0, failed_last_24h: 0)).to eq(:stable)
    end

    it "returns :degraded when 24h has failures but last hour is clean" do
      expect(stability_state(failed_last_hour: 0, failed_last_24h: 3)).to eq(:degraded)
    end

    it "returns :critical when there is any failure in the last hour" do
      expect(stability_state(failed_last_hour: 1, failed_last_24h: 5)).to eq(:critical)
    end

    it "treats nil counts as zero" do
      expect(stability_state(failed_last_hour: nil, failed_last_24h: nil)).to eq(:stable)
    end
  end

  describe "#stability_badge" do
    include ActionView::Helpers::UrlHelper

    it "renders a green pill labelled Stable when stable" do
      result = stability_badge(failed_last_hour: 0, failed_last_24h: 0)

      expect(result).to include("so-badge--pill")
      expect(result).to include("so-badge--success")
      expect(result).to include("Stable")
      expect(result).to include("<svg")
      expect(result).to include('viewBox="0 0 6 6"')
    end

    it "renders an amber pill labelled Degraded for 24h failures only" do
      result = stability_badge(failed_last_hour: 0, failed_last_24h: 4)

      expect(result).to include("so-badge--warning")
      expect(result).to include("Degraded")
    end

    it "renders a red pill labelled Critical when there is any failure in the last hour" do
      result = stability_badge(failed_last_hour: 2, failed_last_24h: 9)

      expect(result).to include("so-badge--danger")
      expect(result).to include("Critical")
    end
  end

  describe "#stability_detail" do
    include ActionView::Helpers::DateHelper
    include ActionView::Helpers::TextHelper

    it "states the stable case explicitly" do
      expect(stability_detail(failed_last_24h: 0, latest_failure_at: nil))
        .to eq("No failures in the last 24h")
    end

    it "pluralises and includes latest-failure age" do
      latest = 17.minutes.ago
      result = stability_detail(failed_last_24h: 3, latest_failure_at: latest)

      expect(result).to start_with("3 failures in the last 24h, latest ")
      expect(result).to include("ago")
    end

    it "uses singular form for one failure" do
      result = stability_detail(failed_last_24h: 1, latest_failure_at: 5.minutes.ago)
      expect(result).to start_with("1 failure in the last 24h")
    end

    it "falls back to 'unknown' when latest timestamp is missing" do
      result = stability_detail(failed_last_24h: 2, latest_failure_at: nil)
      expect(result).to include("latest unknown")
    end
  end

  describe "alert indicators" do
    after { SolidObserver.reset_configuration! }

    def stub_count(value)
      allow(SolidObserver::Services::AlertStatus).to receive(:active_count).and_return(value)
    end

    def stub_raise(error)
      allow(SolidObserver::Services::AlertStatus).to receive(:active_count).and_raise(error)
    end

    describe "#alerts_component_enabled?" do
      it "is true when alerts are on in persistence mode" do
        SolidObserver.config.alerts_enabled = true
        SolidObserver.config.storage_mode = :persistence

        expect(alerts_component_enabled?).to be true
      end

      it "is false when alerts are off" do
        SolidObserver.config.alerts_enabled = false

        expect(alerts_component_enabled?).to be false
      end

      it "is false in realtime mode" do
        SolidObserver.config.alerts_enabled = true
        SolidObserver.config.storage_mode = :realtime

        expect(alerts_component_enabled?).to be false
      end
    end

    describe "#active_alert_count" do
      it "delegates to Services::AlertStatus" do
        stub_count(4)

        expect(active_alert_count).to eq(4)
      end

      it "queries once per request even when zero" do
        stub_count(0)

        2.times { active_alert_count }

        expect(SolidObserver::Services::AlertStatus).to have_received(:active_count).once
      end

      # The layout renders this on every page, including the storage-unavailable
      # error page, so no storage failure may escape as a 500.
      [
        ActiveRecord::StatementInvalid.new("no such table: solid_observer_alert_histories"),
        ActiveRecord::ConnectionNotEstablished.new,
        ActiveRecord::NoDatabaseError.new,
        TypeError.new("nil is not a symbol")
      ].each do |error|
        it "degrades to 0 on #{error.class}" do
          stub_raise(error)

          expect { @degraded = active_alert_count }.not_to raise_error
          expect(@degraded).to eq(0)
        end
      end
    end

    describe "#alerts_nav_label" do
      it "is a plain label when nothing is firing" do
        stub_count(0)

        expect(alerts_nav_label).to eq("Alerts")
      end

      it "carries a count badge when alerts are firing" do
        stub_count(3)

        expect(alerts_nav_label).to include('<span class="so-badge so-badge--pill so-badge--danger"')
        expect(alerts_nav_label).to include(">3</span>")
      end

      it "labels the badge for screen readers" do
        stub_count(1)

        expect(alerts_nav_label).to include('aria-label="1 active alert"')
      end
    end
  end
end
