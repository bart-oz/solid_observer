# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/solid_observer/services/health_score"

RSpec.describe SolidObserver::Services::HealthScore do
  after { SolidObserver.reset_configuration! }

  let(:stable_queue_snapshot) do
    {available: true, failed_last_hour: 0, failed_last_24h: 0}
  end

  let(:stable_cache_response) do
    {stability: {available: true, state: :stable}}
  end

  let(:stable_cable_response) do
    {stability: {available: true, state: :stable}}
  end

  def enable_all_components
    SolidObserver.configure do |config|
      config.observe_queue = true
      config.observe_cache = true
      config.observe_cable = true
    end
    stub_const("SolidCache", Module.new)
    stub_const("SolidCable", Module.new)
  end

  def stub_queue(snapshot = stable_queue_snapshot)
    allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(snapshot)
  end

  def stub_cache(response = stable_cache_response)
    allow(SolidObserver::Services::CacheStats).to receive(:call).and_return(response)
  end

  def stub_cable(response = stable_cable_response)
    allow(SolidObserver::Services::CableStats).to receive(:call).and_return(response)
  end

  def stub_all(queue: stable_queue_snapshot, cache: stable_cache_response, cable: stable_cable_response)
    stub_queue(queue)
    stub_cache(cache)
    stub_cable(cable)
  end

  describe ".call" do
    context "when all three components are stable" do
      before do
        enable_all_components
        stub_all
      end

      it "returns overall :stable with all components stable" do
        result = described_class.call
        expect(result[:overall]).to eq(:stable)
        expect(result[:components][:queue]).to eq({status: :stable, available: true})
        expect(result[:components][:cache]).to eq({status: :stable, available: true})
        expect(result[:components][:cable]).to eq({status: :stable, available: true})
      end
    end

    context "when one component is critical among mixed statuses" do
      before do
        enable_all_components
        stub_all(
          queue: stable_queue_snapshot.merge(failed_last_hour: 3),
          cache: {stability: {available: true, state: :degraded}},
          cable: stable_cable_response
        )
      end

      it "returns overall :critical" do
        result = described_class.call
        expect(result[:overall]).to eq(:critical)
        expect(result[:components][:queue][:status]).to eq(:critical)
        expect(result[:components][:cache][:status]).to eq(:degraded)
        expect(result[:components][:cable][:status]).to eq(:stable)
      end
    end

    context "when one component is degraded and rest are stable" do
      before do
        enable_all_components
        stub_all(
          queue: stable_queue_snapshot.merge(failed_last_24h: 2, failed_last_hour: 0),
          cache: stable_cache_response,
          cable: stable_cable_response
        )
      end

      it "returns overall :degraded" do
        result = described_class.call
        expect(result[:overall]).to eq(:degraded)
        expect(result[:components][:queue][:status]).to eq(:degraded)
        expect(result[:components][:cache][:status]).to eq(:stable)
        expect(result[:components][:cable][:status]).to eq(:stable)
      end
    end

    context "when observe_cache and observe_cable are false" do
      before do
        SolidObserver.configure do |config|
          config.observe_queue = true
          config.observe_cache = false
          config.observe_cable = false
        end
        stub_queue
      end

      it "omits cache and cable keys from components" do
        result = described_class.call
        expect(result[:components]).to have_key(:queue)
        expect(result[:components]).not_to have_key(:cache)
        expect(result[:components]).not_to have_key(:cable)
      end
    end

    context "when realtime_mode is enabled" do
      before do
        SolidObserver.configure do |config|
          config.observe_queue = true
          config.observe_cache = true
          config.observe_cable = true
          config.storage_mode = :realtime
        end
        stub_const("SolidCache", Module.new)
        stub_const("SolidCable", Module.new)
        stub_queue
      end

      it "evaluates only queue, omitting cache and cable" do
        expect(SolidObserver::Services::CacheStats).not_to receive(:call)
        expect(SolidObserver::Services::CableStats).not_to receive(:call)

        result = described_class.call
        expect(result[:components]).to have_key(:queue)
        expect(result[:components]).not_to have_key(:cache)
        expect(result[:components]).not_to have_key(:cable)
        expect(result[:overall]).to eq(:stable)
      end
    end

    context "when queue reports available: false" do
      before do
        enable_all_components
        stub_all(queue: {available: false, error: "SolidQueue not available"})
      end

      it "returns queue component as degraded with available: false" do
        result = described_class.call
        expect(result[:components][:queue]).to eq({status: :degraded, available: false})
      end
    end

    context "when cache stability reports available: false" do
      before do
        enable_all_components
        stub_all(cache: {stability: {available: false, state: :stable}})
      end

      it "returns cache component as degraded with available: false" do
        result = described_class.call
        expect(result[:components][:cache]).to eq({status: :degraded, available: false})
      end
    end

    context "when QueueStats.snapshot raises an error" do
      before do
        enable_all_components
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_raise(ActiveRecord::ConnectionNotEstablished)
        stub_cache
        stub_cable
      end

      it "returns queue as degraded while scoring other components" do
        result = described_class.call
        expect(result[:components][:queue]).to eq({status: :degraded, available: false})
        expect(result[:components][:cache][:status]).to eq(:stable)
        expect(result[:components][:cable][:status]).to eq(:stable)
        expect(result[:overall]).to eq(:degraded)
      end
    end

    context "when no components are enabled" do
      before do
        SolidObserver.configure do |config|
          config.observe_queue = false
          config.observe_cache = false
          config.observe_cable = false
        end
      end

      it "returns overall :stable with empty components" do
        result = described_class.call
        expect(result[:overall]).to eq(:stable)
        expect(result[:components]).to eq({})
      end
    end

    context "queue failure thresholds" do
      before do
        enable_all_components
        stub_cache
        stub_cable
      end

      it "returns critical when failed_last_hour is positive" do
        stub_queue(stable_queue_snapshot.merge(failed_last_hour: 1, failed_last_24h: 5))

        result = described_class.call
        expect(result[:components][:queue][:status]).to eq(:critical)
        expect(result[:overall]).to eq(:critical)
      end

      it "returns degraded when only failed_last_24h is positive" do
        stub_queue(stable_queue_snapshot.merge(failed_last_hour: 0, failed_last_24h: 3))

        result = described_class.call
        expect(result[:components][:queue][:status]).to eq(:degraded)
        expect(result[:overall]).to eq(:degraded)
      end
    end
  end
end
