# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::BaseEvent do
  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "inherits from BaseRecord" do
    expect(described_class.superclass).to eq(SolidObserver::BaseRecord)
  end

  it "cannot be instantiated directly" do
    expect { described_class.new }.to raise_error(NotImplementedError)
  end
end
