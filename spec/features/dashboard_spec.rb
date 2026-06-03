# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Dashboard", type: :feature do
  before { SolidObserver.config.storage_mode = :persistence }

  it "has an accessible sr-only h1 instead of visible h1" do
    visit "/solid_observer"
    expect(page).to have_css("h1.sr-only", text: "Dashboard")
    expect(page).not_to have_css(".so-content__header h1", text: "Dashboard")
  end

  it "shows the SolidObserver logo in the sidebar" do
    visit "/solid_observer"
    expect(page).to have_content("SolidObserver")
  end

  it "shows Overview and Jobs navigation links" do
    visit "/solid_observer"
    expect(page).to have_link("Overview")
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
        queues: {"default" => 8, "mailers" => 2},
        available: true,
        range: "15m",
        performed_in_range: 1200,
        failed_in_range: 9,
        enqueued_in_range: 1500,
        avg_duration_in_range: 1.2,
        failed_last_24h: 9,
        failed_last_hour: 0,
        latest_failure_at: nil,
        enqueue_rate_per_min: 4.6,
        performed_by_queue: {"default" => 1100, "mailers" => 100},
        failed_by_queue: {"default" => 8, "mailers" => 1}
      )
      allow(SolidObserver::QueueEvent).to receive(:recent).and_return([])
      allow(SolidObserver::QueueEvent).to receive(:recent_failures).and_return([])
      allow(SolidObserver::QueueStats).to receive(:chart_data).and_return(
        {
          performed: [{t: 100, v: 5}, {t: 200, v: 10}],
          failed: [{t: 100, v: 1}],
          ready: [{t: 100, v: 3}, {t: 200, v: 7}]
        }
      )
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

    it "renders Zone B live-state cards with data-so-zone attribute" do
      visit "/solid_observer"
      expect(page).to have_css('[data-so-zone="live-state"]')
      expect(page).to have_css('[data-so-card-value="ready"]')
      expect(page).to have_css('[data-so-card-value="scheduled"]')
      expect(page).to have_css('[data-so-card-value="claimed"]')
      expect(page).to have_css('[data-so-card-value="workers"]')
      expect(page).to have_css('[data-so-card-value="failed"]')
    end

    it "renders Zone C throughput cards with separated value and suffix nodes" do
      visit "/solid_observer"
      expect(page).to have_css('[data-so-zone="throughput"]')
      expect(page).to have_css('[data-so-card-value="performed_in_range"]')
      expect(page).to have_css('[data-so-card-value="failed_in_range"]')
      expect(page).to have_css('[data-so-card-value="enqueued_in_range"]')
      expect(page).to have_css('[data-so-card-value="avg_duration_in_range"]')
      expect(page).to have_css(".so-metric__suffix", text: "jobs")
      expect(page).to have_css("[data-so-range-copy]", text: "in last 15m")
      # Avg duration value node contains only a number; suffix is "ms"
      avg_card = find('[data-so-card-value="avg_duration_in_range"]')
      expect(avg_card.text).to match(/\A[\d,]+\z/)
      expect(page).to have_css("[data-so-card-suffix]", text: "ms")
    end

    it "renders Zone E per-queue table with live depth and range columns" do
      visit "/solid_observer"
      expect(page).to have_css('[data-so-zone="queue-table"]')
      expect(page).to have_content("Queue throughput")
      expect(page).to have_css("th", text: "Queue")
      expect(page).to have_css("th", text: "Live depth")
      expect(page).to have_content("default")
      expect(page).to have_content("mailers")
    end

    it "renders Zone F Stability strip with badge and detail" do
      visit "/solid_observer"
      expect(page).to have_content("Stability")
      expect(page).to have_link("View failures", href: "/solid_observer/events?event_type=job_failed")
    end

    it "renders the Live toggle with correct markup" do
      visit "/solid_observer"
      expect(page).to have_css('input[data-so-live-toggle][type="checkbox"][name="live"]')
    end

    it "renders checked Live toggle as pill switch when enabled in params" do
      visit "/solid_observer?live=on"

      expect(page).to have_css("[data-so-live]")
      expect(page).to have_css('input[data-so-live-toggle][type="checkbox"][name="live"][value="on"][checked]')
      expect(page).to have_css("label.so-toggle.so-toggle--pill.so-toggle--on")
      expect(page).to have_css(".so-toggle__label", text: "Live")
      expect(page).to have_css(".so-toggle__cadence", text: "5s")
      expect(page).to have_css(".so-toggle__dot")
    end

    it "renders the range selector with data-so-range-select" do
      visit "/solid_observer"
      expect(page).to have_css("[data-so-range-select]")
    end

    it "renders Refresh data button" do
      visit "/solid_observer"
      expect(page).to have_css("[data-so-refresh]", text: "Refresh data")
    end

    it "renders help button with aria-expanded" do
      visit "/solid_observer"
      expect(page).to have_css("[data-so-help-btn][aria-expanded]")
    end

    it "renders help button and panel inside a hover wrapper" do
      visit "/solid_observer"
      expect(page).to have_css("[data-so-help-wrapper]")
      expect(page).to have_css("[data-so-help-wrapper] [data-so-help-btn]")
      expect(page).to have_css("[data-so-help-wrapper] [data-so-help-panel]", visible: false)
    end

    it "renders chart strip with three sparkline figures" do
      visit "/solid_observer"
      expect(page).to have_css('[data-so-spark="performed"]')
      expect(page).to have_css('[data-so-spark="failed"]')
      expect(page).to have_css('[data-so-spark="ready"]')
    end

    it "renders chart indicators with range total values, not latest bucket values" do
      visit "/solid_observer"
      # Performed total shows performed_in_range (1200), not latest bucket (10)
      within('[data-so-spark="performed"]') do
        expect(page).to have_css('[data-so-card-value="performed_in_range"]', text: "1,200")
      end
      # Failed total shows failed_in_range (9), not latest bucket (1)
      within('[data-so-spark="failed"]') do
        expect(page).to have_css('[data-so-card-value="failed_in_range"]', text: "9")
      end
    end

    it "renders chart labels as range totals, not per-minute rates" do
      visit "/solid_observer"
      within('[data-so-spark="performed"]') do
        expect(page).to have_css(".so-spark__label", text: /Performed total/)
        expect(page).not_to have_css(".so-spark__label", text: /Performed\/min/)
      end
      within('[data-so-spark="failed"]') do
        expect(page).to have_css(".so-spark__label", text: /Failed total/)
        expect(page).not_to have_css(".so-spark__label", text: /Failed\/min/)
      end
    end

    it "renders Ready depth chart indicator with data-so-card-value" do
      visit "/solid_observer"
      within('[data-so-spark="ready"]') do
        expect(page).to have_css('[data-so-card-value="ready"]')
      end
    end

    it "does not use data-so-spark-value for chart indicator values" do
      visit "/solid_observer"
      expect(page).not_to have_css("[data-so-spark-value]")
    end

    it "renders chart polylines with non-empty points on first paint" do
      visit "/solid_observer"
      within('[data-so-spark="performed"]') do
        polyline = find(".so-spark__line")
        expect(polyline["points"]).not_to be_empty
      end
    end

    it "keeps selected range for a valid range param" do
      visit "/solid_observer?range=15m"
      expect(page).to have_select("Range", selected: "15m")
    end

    it "falls back selected range for an invalid range param" do
      visit "/solid_observer?range=bogus"
      expect(page).to have_select("Range", selected: "15m")
    end

    it "does not render turbo frame wrappers" do
      visit "/solid_observer"
      expect(page).not_to have_css("turbo-frame")
    end

    it "renders Zone A toolbar with left and right groups" do
      visit "/solid_observer"
      expect(page).to have_css(".so-dashboard-toolbar__left")
      expect(page).to have_css(".so-dashboard-toolbar__right")
    end

    it "renders Zone B section heading" do
      visit "/solid_observer"
      expect(page).to have_css("h2", text: "Right now")
    end

    it "renders Zone C section heading with range subtitle" do
      visit "/solid_observer"
      expect(page).to have_css("h2", text: "Throughput in selected range")
    end

    it "renders Zone D chart section" do
      visit "/solid_observer"
      expect(page).to have_css('[data-so-zone="chart"]')
      expect(page).to have_css("h2", text: "Charts")
    end

    it "renders freshness text area" do
      visit "/solid_observer"
      expect(page).to have_css("[data-so-freshness]")
    end

    it "renders Queue overview header with h1, status badge, and range caption" do
      visit "/solid_observer"
      expect(page).to have_css(".so-content__header h1", text: "Queue overview")
      expect(page).to have_css(".so-badge.so-badge--pill", text: /Available/)
      expect(page).to have_css(".so-queue-overview__intro")
    end
  end

  context "in realtime mode" do
    before do
      SolidObserver.config.storage_mode = :realtime
      allow(SolidObserver::QueueStats).to receive(:chart_data).and_return(
        {performed: [], failed: [], ready: [{t: 100, v: 3}]}
      )
    end

    it "does not show Events and Storage navigation links" do
      visit "/solid_observer"
      expect(page).not_to have_link("Events")
      expect(page).not_to have_link("Storage")
    end

    it "shows Real-time mode indicator" do
      visit "/solid_observer"
      expect(page).to have_content("Real-time")
    end

    it "does not show throughput cards or Stability in realtime mode" do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(
        ready: 1,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 1,
        queues: {},
        available: true,
        range: "15m"
      )

      visit "/solid_observer"

      expect(page).not_to have_css('[data-so-zone="throughput"]')
      expect(page).not_to have_content("Stability")
    end

    it "renders live-state cards in realtime mode" do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(
        ready: 1,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 1,
        queues: {},
        available: true,
        range: "15m"
      )

      visit "/solid_observer?range=15m"

      expect(page).not_to have_css("turbo-frame")
      expect(page).to have_css('[data-so-card-value="ready"]')
      expect(page).to have_css('[data-so-card-value="scheduled"]')
      expect(page).to have_css('[data-so-card-value="claimed"]')
      expect(page).to have_css('[data-so-card-value="workers"]')
      expect(page).to have_css('[data-so-card-value="failed"]')
      expect(page).to have_select("Range", selected: "15m")
    end

    it "renders only the ready sparkline figure" do
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(
        ready: 1,
        scheduled: 0,
        claimed: 0,
        failed: 0,
        workers: 1,
        queues: {},
        available: true,
        range: "15m"
      )

      visit "/solid_observer"

      expect(page).to have_css('[data-so-spark="ready"]')
      expect(page).not_to have_css('[data-so-spark="performed"]')
      expect(page).not_to have_css('[data-so-spark="failed"]')
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
