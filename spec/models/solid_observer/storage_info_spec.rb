# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::StorageInfo do
  it "inherits from BaseEvent" do
    expect(described_class.superclass).to eq(SolidObserver::BaseEvent)
  end

  it "is not abstract (can be instantiated)" do
    expect(described_class.abstract_class?).to be false
  end

  it "uses solid_observer_storage_info table" do
    expect(described_class.table_name).to eq("solid_observer_storage_info")
  end

  it "inherits database connection from BaseEvent" do
    expect(described_class.superclass).to eq(SolidObserver::BaseEvent)
    expect(SolidObserver::BaseEvent.abstract_class?).to be true
  end

  it "has validations defined" do
    expect(described_class.validators.map(&:class)).to include(ActiveRecord::Validations::PresenceValidator)
  end

  it "defines recent scope" do
    expect(described_class).to respond_to(:recent)
  end

  it "defines since scope" do
    expect(described_class).to respond_to(:since)
  end

  it "defines record_snapshot class method" do
    expect(described_class).to respond_to(:record_snapshot)
  end

  it "defines db_size_mb instance method" do
    expect(described_class.instance_methods).to include(:db_size_mb)
  end

  it "defines db_size_gb instance method" do
    expect(described_class.instance_methods).to include(:db_size_gb)
  end
end
