# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueMetric do
  let(:period_start) { Time.utc(2026, 6, 1, 12, 0, 0) }

  before(:all) do
    connection = described_class.connection
    next if connection.table_exists?(:solid_observer_metrics)

    connection.create_table :solid_observer_metrics do |t|
      t.string :metric_name, null: false, limit: 50
      t.bigint :value, null: false, default: 0
      t.datetime :period_start, null: false
      t.string :period_type, null: false, limit: 10
    end

    connection.add_index :solid_observer_metrics, [:metric_name, :period_start, :period_type], unique: true,
      name: "idx_solid_observer_metrics_unique"
  end

  before { described_class.delete_all }

  it "inherits from BaseMetric" do
    expect(described_class.ancestors).to include(SolidObserver::BaseMetric)
  end

  it "is documented as planned for a future release" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/queue_metric.rb"))
    expect(model_content).to include("planned for a future release")
  end

  it "is not an abstract class" do
    expect(described_class.abstract_class?).to be false
  end

  it "uses solid_observer_metrics table" do
    expect(described_class.table_name).to eq("solid_observer_metrics")
  end

  describe ".increment" do
    it "creates a metric row when none exists" do
      metric = described_class.increment(metric: "jobs_completed", period: period_start)

      expect(metric).to have_attributes(
        metric_name: "jobs_completed",
        value: 1,
        period_start: period_start,
        period_type: "hour"
      )
      expect(described_class.count).to eq(1)
    end

    it "increments the existing metric row" do
      described_class.create!(
        metric_name: "jobs_completed",
        value: 1,
        period_start: period_start,
        period_type: "hour"
      )

      metric = described_class.increment(metric: "jobs_completed", period: period_start, by: 2)

      expect(metric.reload.value).to eq(3)
      expect(described_class.count).to eq(1)
    end

    it "retries after a RecordNotUnique race" do
      find_or_create_attempts = 0

      allow(described_class).to receive(:find_or_create_by!).and_wrap_original do |original, *args, **kwargs|
        find_or_create_attempts += 1
        raise ActiveRecord::RecordNotUnique if find_or_create_attempts == 1

        original.call(*args, **kwargs)
      end

      metric = described_class.increment(metric: "jobs_completed", period: period_start)

      expect(metric.reload.value).to eq(1)
      expect(find_or_create_attempts).to eq(2)
    end
  end

  describe ".record" do
    it "upserts the metric row and returns the persisted record" do
      first_record = described_class.record(metric: "jobs_completed", value: 5, period: period_start)
      second_record = described_class.record(metric: "jobs_completed", value: 8, period: period_start)

      expect(described_class.count).to eq(1)
      expect(second_record.id).to eq(first_record.id)
      expect(second_record.reload.value).to eq(8)
    end
  end
end
