# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CacheEvent do
  before(:all) do
    connection = described_class.connection
    next if connection.table_exists?(:solid_observer_cache_events)

    connection.create_table :solid_observer_cache_events do |t|
      t.string :event_type, null: false
      t.string :key_digest, null: false
      t.boolean :hit
      t.float :duration
      t.string :error_class
      t.text :error_message
      t.text :metadata
      t.datetime :recorded_at, null: false
    end
  end

  before { described_class.delete_all }

  it "inherits from BaseEvent" do
    expect(described_class.superclass).to eq(SolidObserver::BaseEvent)
  end

  it "uses solid_observer_cache_events table" do
    expect(described_class.table_name).to eq("solid_observer_cache_events")
  end

  it "validates required fields" do
    record = described_class.new

    expect(record).not_to be_valid
    expect(record.errors[:event_type]).to be_present
    expect(record.errors[:key_digest]).to be_present
    expect(record.errors[:recorded_at]).to be_present
  end
end
