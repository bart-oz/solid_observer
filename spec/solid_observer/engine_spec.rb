# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Engine do
  let(:logger) { instance_double(Logger, warn: nil, info: nil) }

  before do
    allow(Rails).to receive(:logger).and_return(logger)
  end

  it "is a Rails::Engine" do
    expect(described_class.ancestors).to include(Rails::Engine)
  end

  it "isolates namespace to SolidObserver" do
    expect(described_class.isolated?).to be true
  end

  describe ".check_solid_queue_availability" do
    it "warns when SolidQueue is not defined" do
      hide_const("SolidQueue")

      expect(logger).to receive(:warn).with(/SolidQueue not detected/)

      described_class.check_solid_queue_availability
    end

    it "does not warn when SolidQueue is defined" do
      stub_const("SolidQueue", Class.new)

      expect(logger).not_to receive(:warn)

      described_class.check_solid_queue_availability
    end
  end

  describe ".activate_subscribers" do
    let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

    before do
      allow(ActiveRecord::Base).to receive(:connection).and_return(connection)
      allow(SolidObserver::Subscriber).to receive(:subscribe!)
    end

    it "activates subscribers when tables exist" do
      allow(connection).to receive(:table_exists?).with("solid_observer_queue_events").and_return(true)

      expect(logger).to receive(:info).with(/Activating event subscribers/)
      expect(SolidObserver::Subscriber).to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "logs migration instruction when tables do not exist" do
      allow(connection).to receive(:table_exists?).with("solid_observer_queue_events").and_return(false)

      expect(logger).to receive(:info).with(/Tables not found/)
      expect(SolidObserver::Subscriber).not_to receive(:subscribe!)

      described_class.activate_subscribers
    end

    it "rescues gracefully when database is not ready" do
      allow(connection).to receive(:table_exists?).and_raise(ActiveRecord::NoDatabaseError)

      expect(logger).to receive(:info).with(/Database not ready/)

      described_class.activate_subscribers
    end
  end

  describe "routes" do
    it "has a route set" do
      expect(described_class.routes).to be_a(ActionDispatch::Routing::RouteSet)
    end
  end

  describe "configuration" do
    it "activates subscribers after initialization" do
      expect(described_class).to respond_to(:activate_subscribers)
    end
  end
end
