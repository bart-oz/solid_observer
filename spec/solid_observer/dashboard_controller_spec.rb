# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::DashboardController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end
  end

  describe "#index" do
    let(:params_hash) { {} }
    let(:stats) do
      {
        ready: 3,
        scheduled: 1,
        claimed: 0,
        failed: 2,
        workers: 1,
        queues: {},
        available: true,
        range: "1h"
      }
    end
    let(:request_double) do
      instance_double(
        ActionDispatch::Request,
        query_parameters: params_hash.transform_keys(&:to_s)
      )
    end

    before do
      allow(controller).to receive(:request).and_return(request_double)
      allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
    end

    it "assigns @stats from QueueStats.snapshot and exposes available ranges" do
      SolidObserver.config.storage_mode = :realtime
      controller.index

      expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "1h")
      expect(controller.instance_variable_get(:@stats)).to eq(stats)
      expect(controller.instance_variable_get(:@range)).to eq("1h")
    end

    describe "GET #index with range param" do
      context "with a valid range" do
        let(:params_hash) { {range: "15m"} }
        let(:stats) { super().merge(range: "15m") }

        it "uses the provided range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "15m")
          expect(controller.instance_variable_get(:@range)).to eq("15m")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("15m")
        end
      end

      context "with an invalid range" do
        let(:params_hash) { {range: "999d"} }

        it "falls back to the default range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "1h")
          expect(controller.instance_variable_get(:@range)).to eq("1h")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("1h")
        end
      end

      context "with no range" do
        it "falls back to the default range" do
          SolidObserver.config.storage_mode = :realtime
          controller.index

          expect(SolidObserver::QueueStats).to have_received(:snapshot).with(range: "1h")
          expect(controller.instance_variable_get(:@range)).to eq("1h")
          expect(controller.instance_variable_get(:@stats)[:range]).to eq("1h")
        end
      end
    end

    context "in persistence mode" do
      before { SolidObserver.config.storage_mode = :persistence }

      let(:events_scope) { double("events_scope") }
      let(:failures_scope) { double("failures_scope") }
      let(:stats) do
        super().merge(
          performed_in_range: 22,
          failed_in_range: 4,
          enqueue_rate_per_min: 1.8
        )
      end

      before do
        allow(SolidObserver::QueueEvent).to receive(:recent).with(10).and_return(events_scope)
        allow(SolidObserver::QueueEvent).to receive(:recent_failures).with(5).and_return(failures_scope)
      end

      it "assigns persistence-only data and scoped stats" do
        controller.index

        expect(controller.instance_variable_get(:@recent_events)).to eq(events_scope)
        expect(controller.instance_variable_get(:@recent_failures)).to eq(failures_scope)
        expect(controller.instance_variable_get(:@stats)).to include(
          :performed_in_range,
          :failed_in_range,
          :enqueue_rate_per_min
        )
      end
    end

    context "in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      let(:stats) { super().except(:performed_in_range, :failed_in_range, :enqueue_rate_per_min) }

      it "does not assign persistence-only data or scoped keys" do
        controller.index

        expect(controller.instance_variable_get(:@recent_events)).to be_nil
        expect(controller.instance_variable_get(:@recent_failures)).to be_nil
        expect(controller.instance_variable_get(:@stats)).not_to include(
          :performed_in_range,
          :failed_in_range,
          :enqueue_rate_per_min
        )
      end
    end
  end
end
