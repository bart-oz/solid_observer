# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueMetric do
  it "inherits from BaseMetric" do
    expect(described_class.ancestors).to include(SolidObserver::BaseMetric)
  end

  it "uses connects_to for database configuration" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/queue_metric.rb"))
    expect(model_content).to include("connects_to")
    expect(model_content).to include("solid_observer_queue")
  end

  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "uses solid_observer_metrics table" do
    expect(described_class.table_name).to eq("solid_observer_metrics")
  end
end
