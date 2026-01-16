# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::StorageInfo do
  it "is an abstract class" do
    expect(described_class.abstract_class?).to be true
  end

  it "cannot be instantiated directly" do
    expect { described_class.new }.to raise_error(NotImplementedError)
  end

  it "uses solid_observer_storage_info table" do
    expect(described_class.table_name).to eq("solid_observer_storage_info")
  end

  it "uses connects_to for database configuration" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/storage_info.rb"))
    expect(model_content).to include("connects_to")
    expect(model_content).to include("solid_observer_queue")
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
