# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueMetric do
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
end
