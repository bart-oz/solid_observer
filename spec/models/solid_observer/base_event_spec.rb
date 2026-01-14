# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::BaseEvent do
  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "inherits from ActiveRecord::Base" do
    expect(described_class.ancestors).to include(ActiveRecord::Base)
  end

  it "cannot be instantiated directly" do
    expect { described_class.new }.to raise_error(NotImplementedError)
  end
end
