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

    it "registers :set_event as a before_action only for show" do
      callbacks = described_class._process_action_callbacks.select { |cb| cb.filter == :set_event }
      expect(callbacks).not_to be_empty
      expect(callbacks.first.kind).to eq(:before)
    end

    it "defines PER_PAGE as 50" do
      expect(described_class::PER_PAGE).to eq(50)
    end
  end

  describe "#set_filter_params" do
    it "extracts event_type from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(event_type: "job_failed"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@event_type)).to eq("job_failed")
    end

    it "extracts job_class from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(job_class: "MyJob"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@job_class)).to eq("MyJob")
    end

    it "extracts queue_name from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(queue_name: "default"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@queue_name)).to eq("default")
    end

    it "defaults @page to 1 when not given" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@page)).to eq(1)
    end

    it "converts page to integer" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(page: "4"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@page)).to eq(4)
    end

    it "parses from date" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(from: "2026-01-01"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@from)).to eq(Date.new(2026, 1, 1))
    end

    it "parses to date" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(to: "2026-01-31"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@to)).to eq(Date.new(2026, 1, 31))
    end
  end

  describe "#build_event_scope" do
    let(:base_scope) { double("base_scope") }

    before do
      allow(SolidObserver::QueueEvent).to receive(:order).with(recorded_at: :desc).and_return(base_scope)
      controller.instance_variable_set(:@event_type, nil)
      controller.instance_variable_set(:@job_class, nil)
      controller.instance_variable_set(:@queue_name, nil)
      controller.instance_variable_set(:@from, nil)
      controller.instance_variable_set(:@to, nil)
    end

    it "returns base scope when no filters set" do
      expect(controller.send(:build_event_scope)).to eq(base_scope)
    end

    it "applies event_type filter" do
      controller.instance_variable_set(:@event_type, "job_failed")
      filtered = double("filtered")
      allow(base_scope).to receive(:by_event_type).with("job_failed").and_return(filtered)
      expect(controller.send(:build_event_scope)).to eq(filtered)
    end

    it "applies job_class filter" do
      controller.instance_variable_set(:@job_class, "MyJob")
      filtered = double("filtered")
      allow(base_scope).to receive(:by_job_class).with("MyJob").and_return(filtered)
      expect(controller.send(:build_event_scope)).to eq(filtered)
    end

    it "applies queue_name filter" do
      controller.instance_variable_set(:@queue_name, "default")
      filtered = double("filtered")
      allow(base_scope).to receive(:by_queue).with("default").and_return(filtered)
      expect(controller.send(:build_event_scope)).to eq(filtered)
    end

    it "applies from date filter" do
      date = Date.new(2026, 1, 1)
      controller.instance_variable_set(:@from, date)
      filtered = double("filtered")
      allow(base_scope).to receive(:since).with(date.beginning_of_day).and_return(filtered)
      expect(controller.send(:build_event_scope)).to eq(filtered)
    end

    it "applies to date filter" do
      date = Date.new(2026, 1, 31)
      controller.instance_variable_set(:@to, date)
      filtered = double("filtered")
      allow(base_scope).to receive(:before).with(date.end_of_day).and_return(filtered)
      expect(controller.send(:build_event_scope)).to eq(filtered)
    end
  end

  describe "#set_event" do
    context "when event exists" do
      let(:event) { double("event") }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "1"))
        allow(SolidObserver::QueueEvent).to receive(:find_by).with(id: "1").and_return(event)
      end

      it "assigns @event" do
        controller.send(:set_event)
        expect(controller.instance_variable_get(:@event)).to eq(event)
      end

      it "does not redirect" do
        expect(controller).not_to receive(:redirect_to)
        controller.send(:set_event)
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
        controller.send(:set_event)
      end
    end
  end

  describe "#parse_date" do
    it "returns nil for blank string" do
      expect(controller.send(:parse_date, "")).to be_nil
    end

    it "returns nil for nil" do
      expect(controller.send(:parse_date, nil)).to be_nil
    end

    it "parses a valid date string" do
      expect(controller.send(:parse_date, "2026-04-06")).to eq(Date.new(2026, 4, 6))
    end

    it "returns nil for invalid date" do
      expect(controller.send(:parse_date, "not-a-date")).to be_nil
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

    it "sets @available_event_types from EVENT_TYPES constant" do
      controller.send(:load_available_options)
      expect(controller.instance_variable_get(:@available_event_types)).to eq(SolidObserver::QueueEvent::EVENT_TYPES)
    end

    it "invokes each distinct scope once on cold cache then serves from cache" do
      expect(SolidObserver::QueueEvent).to receive(:distinct_job_classes).once.and_return(["A"])
      expect(SolidObserver::QueueEvent).to receive(:distinct_queue_names).once.and_return(["q"])

      controller.send(:load_available_options)
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
