# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Queries::EventsQuery do
  let(:filter_class) { Struct.new(:event_type, :job_class, :queue_name, :from, :to, keyword_init: true) }

  def build_filter(event_type: nil, job_class: nil, queue_name: nil, from: nil, to: nil)
    filter_class.new(event_type: event_type, job_class: job_class, queue_name: queue_name, from: from, to: to)
  end

  let(:base_scope) { double("base_scope") }

  before do
    allow(SolidObserver::QueueEvent).to receive(:order).with(recorded_at: :desc).and_return(base_scope)
  end

  it "returns base scope when no filters set" do
    expect(described_class.new(build_filter).call).to eq(base_scope)
  end

  it "applies event_type filter" do
    filtered_scope = double("filtered_scope")
    allow(base_scope).to receive(:by_event_type).with("job_failed").and_return(filtered_scope)
    expect(described_class.new(build_filter(event_type: "job_failed")).call).to eq(filtered_scope)
  end

  it "applies job_class filter" do
    filtered_scope = double("filtered_scope")
    allow(base_scope).to receive(:by_job_class).with("MyJob").and_return(filtered_scope)
    expect(described_class.new(build_filter(job_class: "MyJob")).call).to eq(filtered_scope)
  end

  it "applies queue_name filter" do
    filtered_scope = double("filtered_scope")
    allow(base_scope).to receive(:by_queue).with("default").and_return(filtered_scope)
    expect(described_class.new(build_filter(queue_name: "default")).call).to eq(filtered_scope)
  end

  it "applies from date filter" do
    date = Date.new(2026, 1, 1)
    filtered_scope = double("filtered_scope")
    allow(base_scope).to receive(:since).with(date.beginning_of_day).and_return(filtered_scope)
    expect(described_class.new(build_filter(from: date)).call).to eq(filtered_scope)
  end

  it "applies to date filter" do
    date = Date.new(2026, 1, 31)
    filtered_scope = double("filtered_scope")
    allow(base_scope).to receive(:before).with(date.end_of_day).and_return(filtered_scope)
    expect(described_class.new(build_filter(to: date)).call).to eq(filtered_scope)
  end
end
