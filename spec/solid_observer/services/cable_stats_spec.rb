# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/solid_observer/services/cable_stats"

RSpec.describe SolidObserver::Services::CableStats do
  before(:all) do
    connection = SolidObserver::CableMetric.connection
    next if connection.table_exists?(:solid_observer_cable_metrics)

    connection.create_table :solid_observer_cable_metrics do |t|
      t.datetime :period_start, null: false
      t.bigint :broadcasts_count, null: false, default: 0
      t.bigint :transmissions_count, null: false, default: 0
      t.bigint :confirmations_count, null: false, default: 0
      t.bigint :rejections_count, null: false, default: 0
      t.bigint :perform_actions_count, null: false, default: 0
      t.bigint :errors_count, null: false, default: 0
    end
  end

  before(:all) do
    connection = SolidObserver::CableEvent.connection
    next if connection.table_exists?(:solid_observer_cable_events)

    connection.create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false, limit: 64
      t.string :channel_class, limit: 255
      t.string :broadcasting_digest, limit: 64
      t.float :duration
      t.string :error_class, limit: 255
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
      t.string :correlation_id, limit: 64
    end
  end

  before do
    SolidObserver::CableMetric.delete_all
    SolidObserver::CableEvent.delete_all
  end

  after { SolidObserver.reset_configuration! }

  describe ".parse_range" do
    it "returns the requested range when it is supported" do
      expect(described_class.parse_range("1h")).to eq("1h")
    end

    it "falls back to the default range for unsupported values" do
      expect(described_class.parse_range("bogus")).to eq("15m")
    end
  end

  describe ".range_duration" do
    it "returns the configured duration for a range key" do
      expect(described_class.range_duration("1h")).to eq(1.hour)
    end

    it "uses the default duration for unsupported values" do
      expect(described_class.range_duration("bogus")).to eq(15.minutes)
    end
  end

  describe described_class::TrendData do
    let(:fixed_time) { Time.utc(2026, 6, 3, 12, 0, 0) }

    it "returns the empty trend payload when no metric rows exist" do
      result = described_class.new(metric_rows: [], window: 15.minutes, current_time: fixed_time).to_h

      expect(result).to eq(SolidObserver::Services::CableStats::ACTIVITY_TREND_EMPTY)
      expect(result).not_to be(SolidObserver::Services::CableStats::ACTIVITY_TREND_EMPTY)
    end

    it "buckets metric rows and builds broadcasts and rejections series" do
      result = described_class.new(
        metric_rows: [
          [fixed_time - 14.minutes + 45.seconds, 10, 0, 0, 1, 0, 0],
          [fixed_time - 14.minutes + 10.seconds, 2, 0, 0, 1, 0, 0],
          [fixed_time - 2.minutes + 30.seconds, 5, 0, 0, 0, 0, 0]
        ],
        window: 15.minutes,
        current_time: fixed_time
      ).to_h

      broadcasts_by_time = result[:broadcasts].to_h { |point| [point[:t], point[:v]] }
      rejections_by_time = result[:rejections].to_h { |point| [point[:t], point[:v]] }

      expect(result[:available]).to be(true)
      expect(broadcasts_by_time[(fixed_time - 14.minutes).to_i]).to eq(12)
      expect(rejections_by_time[(fixed_time - 14.minutes).to_i]).to eq(2)
      expect(broadcasts_by_time[(fixed_time - 2.minutes).to_i]).to eq(5)
      expect(rejections_by_time[(fixed_time - 2.minutes).to_i]).to eq(0)
    end
  end

  describe described_class::StabilityData do
    let(:fixed_time) { Time.utc(2026, 6, 3, 12, 0, 0) }

    def stability_data(metric_broadcasts: 0, metric_rejections: 0, backlog_ratio: 0.0, backlog_available: true)
      described_class.new(
        window: 15.minutes,
        current_time: Time.current,
        backlog_snapshot: {available: backlog_available, ratio: backlog_ratio}
      ).to_h(
        metric_broadcasts_count: metric_broadcasts,
        metric_rejections_count: metric_rejections
      )
    end

    around do |example|
      travel_to(fixed_time) { example.run }
    end

    it "classifies the range as stable when no errors, rejections, or backlog pressure exist" do
      expect(stability_data).to include(
        available: true,
        state: :stable,
        rejection_count: 0,
        error_count: 0,
        backlog_available: true
      )
    end

    it "classifies the range as degraded when backlog ratio crosses the threshold" do
      expect(stability_data(backlog_ratio: 0.15)).to include(
        available: true,
        state: :degraded,
        backlog_ratio: 0.15
      )
    end

    it "classifies the range as degraded when rejections are present below the threshold" do
      SolidObserver::CableMetric.create!(
        period_start: fixed_time.beginning_of_minute,
        broadcasts_count: 100,
        rejections_count: 1
      )

      expect(stability_data(metric_broadcasts: 100, metric_rejections: 1)).to include(
        available: true,
        state: :degraded,
        rejection_rate: 0.01
      )
    end

    it "classifies the range as critical when the rejection rate crosses the threshold" do
      expect(stability_data(metric_broadcasts: 100, metric_rejections: 10)).to include(
        available: true,
        state: :critical,
        rejection_rate: 0.1
      )
    end

    it "classifies the range as critical when error events are present" do
      SolidObserver::CableEvent.create!(
        event_type: "broadcast",
        channel_class: "ChatChannel",
        broadcasting_digest: "digest",
        duration: 0.01,
        error_class: "RuntimeError",
        error_message: "hidden from UI",
        metadata: "{}",
        recorded_at: 5.minutes.ago
      )

      expect(stability_data).to include(
        available: true,
        state: :critical,
        error_count: 1,
        rejection_count: 0
      )
    end

    it "classifies the range as critical when backlog reaches the 50% ceiling" do
      expect(stability_data(backlog_ratio: 0.5)).to include(
        available: true,
        state: :critical,
        backlog_ratio: 0.5
      )
    end

    it "classifies the range as degraded when the backlog snapshot is unavailable" do
      expect(stability_data(backlog_available: false)).to include(
        available: true,
        state: :degraded,
        backlog_available: false
      )
    end

    it "tracks the latest recorded at timestamp for rejection and error events" do
      recorded_at = fixed_time - 4.minutes
      SolidObserver::CableEvent.create!(
        event_type: "transmit_subscription_rejection",
        channel_class: "ChatChannel",
        broadcasting_digest: "digest",
        duration: 0.01,
        metadata: "{}",
        recorded_at: recorded_at
      )
      event = SolidObserver::CableEvent.last
      result = stability_data(metric_broadcasts: 100, metric_rejections: 1)

      expect(result).to include(
        available: true,
        state: :degraded,
        rejection_count: 1
      )
      expect(result[:latest_recorded_at].strftime("%Y-%m-%d %H:%M:%S")).to eq(event.recorded_at.strftime("%Y-%m-%d %H:%M:%S"))
    end
  end

  it "returns dashboard-ready aggregated cable stats for window" do
    now = Time.current
    SolidObserver::CableMetric.create!(
      period_start: now.beginning_of_minute,
      broadcasts_count: 100,
      transmissions_count: 90,
      confirmations_count: 80,
      rejections_count: 5,
      perform_actions_count: 10,
      errors_count: 2
    )

    allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return([
      {
        component: "solid_cable",
        available: true,
        event_count: 100,
        trimmable_count: 10
      }
    ])

    stats = described_class.call(window: 5.minutes)

    expect(stats[:broadcasts_count]).to eq(100)
    expect(stats[:rejections_count]).to eq(5)
    expect(stats[:errors_count]).to eq(2)
    expect(stats[:rejection_rate]).to eq(0.05)
    expect(stats[:backlog_count]).to eq(10)
    expect(stats[:backlog_available]).to be(true)
    expect(stats[:stability]).to include(available: true, state: :critical)
  end

  it "returns safe fallback when metric table query fails" do
    allow(SolidObserver::CableMetric).to receive(:where).and_raise(ActiveRecord::StatementInvalid.new("missing table"))

    stats = described_class.call(window: 5.minutes)

    expect(stats).to include(
      broadcasts_count: 0,
      rejections_count: 0,
      errors_count: 0,
      rejection_rate: 0.0,
      backlog_available: false
    )
    expect(stats[:error]).to eq("Service temporarily unavailable")
  end

  it "degrades stability on ActiveRecord::StatementInvalid from cable events query, preserving other data" do
    now = Time.current
    SolidObserver::CableMetric.create!(
      period_start: now.beginning_of_minute,
      broadcasts_count: 100,
      rejections_count: 5
    )

    allow(SolidObserver::CableEvent).to receive(:where).and_raise(
      ActiveRecord::StatementInvalid.new("no such table: solid_observer_cable_events")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats).not_to have_key(:error)
    expect(stats[:broadcasts_count]).to eq(100)
    expect(stats[:stability]).to include(available: true, state: :degraded)
  end

  it "preserves metric totals and trends when only the cable events (stability) query fails" do
    now = Time.current
    SolidObserver::CableMetric.create!(
      period_start: now.beginning_of_minute,
      broadcasts_count: 100,
      rejections_count: 5
    )

    allow(SolidObserver::CableEvent).to receive(:where).and_raise(
      ActiveRecord::StatementInvalid.new("no such table: solid_observer_cable_events")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats).not_to have_key(:error)
    expect(stats[:broadcasts_count]).to eq(100)
    expect(stats[:activity_trends][:available]).to be(true)
    expect(stats[:stability]).to include(available: true, state: :degraded)
  end

  it "sanitizes non-ActiveRecord errors in fallback" do
    allow(SolidObserver::CableMetric).to receive(:where).and_raise(
      TypeError.new("no implicit conversion of nil into String")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:error]).to eq("Service temporarily unavailable")
  end

  it "sanitizes generic RuntimeError in fallback without leaking message" do
    allow(SolidObserver::CableMetric).to receive(:where).and_raise(
      RuntimeError.new("PG::DuplicateTable: relation already exists")
    )

    stats = described_class.call(window: 5.minutes)

    expect(stats[:error]).to eq("Service temporarily unavailable")
  end
end
