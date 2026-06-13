# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::BaseRecord do
  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "has no table_name (abstract class marker)" do
    expect(described_class.table_name).to be_nil
  end

  it "inherits from ActiveRecord::Base" do
    expect(described_class.superclass).to eq(ActiveRecord::Base)
  end

  it "cannot be instantiated directly" do
    expect { described_class.new }.to raise_error(NotImplementedError)
  end

  it "serves as the shared connection root for all SolidObserver models" do
    expect(SolidObserver::BaseEvent.ancestors).to include(described_class)
    expect(SolidObserver::BaseMetric.ancestors).to include(described_class)
    expect(SolidObserver::CacheMetric.ancestors).to include(described_class)
    expect(SolidObserver::QueueMetric.ancestors).to include(described_class)
  end

  describe "PostgreSQL adapter safeguard (L0050)" do
    it "has a nil table_name that would cause TypeError if queried directly on PG" do
      # Calling query methods (e.g. .count) on an abstract class with nil table_name
      # raises TypeError on PostgreSQL (not ActiveRecord::StatementInvalid).
      # This is a known trap — see L0050. Concrete subclasses must be used instead.
      expect(described_class.table_name).to be_nil
      expect(described_class.abstract_class?).to be true
    end
  end
end
