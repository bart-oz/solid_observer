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

  it "uses connects_to for database configuration" do
    model_content = File.read(File.join(__dir__, "../../../app/models/solid_observer/queue_event.rb"))
    expect(model_content).to include("connects_to")
    expect(model_content).to include("solid_observer_queue")
  end
end
