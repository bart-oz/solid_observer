# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::EventsController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end

    it "registers :require_persistence_mode as a before_action" do
      callbacks = described_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_persistence_mode)
    end

    it "defines PER_PAGE as 50" do
      expect(described_class::PER_PAGE).to eq(50)
    end
  end

  describe "#index" do
    let(:from) { Date.new(2026, 1, 1) }
    let(:to) { Date.new(2026, 1, 31) }
    let(:filter) do
      filter_values = {
        page: 2,
        event_type: "job_failed",
        job_class: "MyJob",
        queue_name: "default",
        from: from,
        to: to
      }
      instance_double(SolidObserver::Params::EventsFilter, **filter_values)
    end
    let(:scope) { double("scope") }
    let(:limited_scope) { double("limited_scope") }
    let(:events) { [double("event")] }
    let(:query) { instance_double(SolidObserver::Queries::EventsQuery, call: scope) }

    before do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      allow(SolidObserver::Params::EventsFilter).to receive(:from_params).and_return(filter)
      allow(SolidObserver::Queries::EventsQuery).to receive(:new).with(filter).and_return(query)
      allow(controller).to receive(:paginate_scope).with(scope, per_page: described_class::PER_PAGE).and_return(50)
      allow(scope).to receive(:limit).with(described_class::PER_PAGE).and_return(limited_scope)
      allow(limited_scope).to receive(:offset).with(50).and_return(events)
      allow(controller).to receive(:load_available_options).and_return({})
    end

    it "assigns @events" do
      controller.send(:index)
      expect(controller.instance_variable_get(:@events)).to eq(events)
    end

    it "assigns legacy filter ivars" do
      controller.send(:index)
      expect(controller.instance_variable_get(:@event_type)).to eq("job_failed")
      expect(controller.instance_variable_get(:@job_class)).to eq("MyJob")
      expect(controller.instance_variable_get(:@queue_name)).to eq("default")
      expect(controller.instance_variable_get(:@from)).to eq(from)
      expect(controller.instance_variable_get(:@to)).to eq(to)
      expect(controller.instance_variable_get(:@page)).to eq(2)
    end
  end

  describe "#show" do
    context "when event exists" do
      let(:event) { double("event", metadata: '{"key":"value"}') }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "1"))
        allow(SolidObserver::QueueEvent).to receive(:find_by).with(id: "1").and_return(event)
      end

      it "assigns @event" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@event)).to eq(event)
      end

      it "assigns parsed metadata" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@metadata)).to eq({"key" => "value"})
      end
    end

    context "when event does not exist" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "999"))
        allow(SolidObserver::QueueEvent).to receive(:find_by).with(id: "999").and_return(nil)
        controller.define_singleton_method(:events_path) { "/solid_observer/events" }
      end

      it "redirects with an alert" do
        expect(controller).to receive(:redirect_to).with("/solid_observer/events", alert: "Event not found")
        controller.send(:show)
      end
    end
  end

  describe "#parse_metadata" do
    it "returns nil for blank string" do
      expect(controller.send(:parse_metadata, "")).to be_nil
    end

    it "returns nil for nil" do
      expect(controller.send(:parse_metadata, nil)).to be_nil
    end

    it "parses valid JSON" do
      expect(controller.send(:parse_metadata, '{"key":"value"}')).to eq({"key" => "value"})
    end

    it "returns raw hash for invalid JSON" do
      expect(controller.send(:parse_metadata, "not json")).to eq({raw: "not json"})
    end
  end

  describe "#load_available_options" do
    before do
      SolidObserver.config.filter_cache_ttl = 1.minute
      allow(SolidObserver::QueueEvent).to receive(:distinct_job_classes).and_return(["MyJob", "OtherJob"])
      allow(SolidObserver::QueueEvent).to receive(:distinct_queue_names).and_return(%w[default urgent])
    end

    it "assigns available event types from EVENT_TYPES constant" do
      controller.send(:load_available_options)
      expect(controller.instance_variable_get(:@available_event_types)).to eq(SolidObserver::QueueEvent::EVENT_TYPES)
    end

    it "invokes each distinct scope once on cold cache then serves from cache" do
      expect(SolidObserver::QueueEvent).to receive(:distinct_job_classes).once.and_return(["A"])
      expect(SolidObserver::QueueEvent).to receive(:distinct_queue_names).once.and_return(["q"])

      controller.send(:load_available_options)
      expect(controller.instance_variable_get(:@available_job_classes)).to eq(["A"])
      expect(controller.instance_variable_get(:@available_queues)).to eq(["q"])

      controller.send(:load_available_options)
      expect(controller.instance_variable_get(:@available_job_classes)).to eq(["A"])
      expect(controller.instance_variable_get(:@available_queues)).to eq(["q"])
    end

    it "does not invoke scopes on hot cache" do
      controller.send(:load_available_options)

      expect(SolidObserver::QueueEvent).not_to receive(:distinct_job_classes)
      expect(SolidObserver::QueueEvent).not_to receive(:distinct_queue_names)

      controller.send(:load_available_options)
    end

    it "re-invokes scope after TTL expiry" do
      expect(SolidObserver::QueueEvent).to receive(:distinct_job_classes).twice.and_return(["A"])
      expect(SolidObserver::QueueEvent).to receive(:distinct_queue_names).twice.and_return(["q"])

      controller.send(:load_available_options)
      travel_to(2.minutes.from_now) do
        controller.send(:load_available_options)
      end
    end
  end
end
