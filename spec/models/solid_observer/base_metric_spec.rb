# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::BaseMetric do
  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "cannot be instantiated directly" do
    expect { described_class.new }.to raise_error(NotImplementedError)
  end

  it "defines PERIOD_TYPES constant" do
    expect(described_class::PERIOD_TYPES).to eq(%w[minute hour day])
  end

  it "has validations defined" do
    expect(described_class.validators.map(&:class)).to include(ActiveRecord::Validations::PresenceValidator)
  end

  it "defines for_metric scope" do
    expect(described_class).to respond_to(:for_metric)
  end

  it "defines hourly scope" do
    expect(described_class).to respond_to(:hourly)
  end

  it "defines daily scope" do
    expect(described_class).to respond_to(:daily)
  end

  it "defines minutely scope" do
    expect(described_class).to respond_to(:minutely)
  end

  it "defines since scope" do
    expect(described_class).to respond_to(:since)
  end

  it "defines between scope" do
    expect(described_class).to respond_to(:between)
  end

  it "defines increment class method" do
    expect(described_class).to respond_to(:increment)
  end

  it "defines record class method" do
    expect(described_class).to respond_to(:record)
  end
end
