# frozen_string_literal: true

require "spec_helper"

RSpec.describe "SolidObserver::QueueEvent" do
  it "model file exists" do
    model_path = File.join(__dir__, "../../../app/models/solid_observer/queue_event.rb")
    expect(File.exist?(model_path)).to be true
  end

  it "inherits from BaseEvent" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/queue_event.rb"))
    expect(model_content).to include("< BaseEvent")
  end

  it "inherits database connection from BaseEvent" do
    expect(SolidObserver::QueueEvent.superclass).to eq(SolidObserver::BaseEvent)
  end

  it "uses solid_observer_queue_events table" do
    expect(SolidObserver::QueueEvent.table_name).to eq("solid_observer_queue_events")
  end
end
