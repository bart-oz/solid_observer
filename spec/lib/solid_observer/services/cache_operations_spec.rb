# frozen_string_literal: true

require "spec_helper"
require_relative "../../../../lib/solid_observer/services/cache_operations"

RSpec.describe SolidObserver::Services::CacheOperations do
  let(:logger) { instance_double(Logger, warn: nil) }
  let(:entry_class) do
    Class.new do
      class << self
        attr_reader :expire_calls

        def expire(*args, **kwargs)
          @expire_calls ||= []
          @expire_calls << {args: args, kwargs: kwargs}
        end
      end
    end
  end
  let(:store_class) do
    Class.new do
      attr_reader :cleanup_calls,
        :clear_calls,
        :connection_passes,
        :expiry_batch_size,
        :max_age,
        :max_entries,
        :max_size

      def initialize
        @cleanup_calls = 0
        @clear_calls = 0
        @connection_passes = 0
        @expiry_batch_size = 12
        @max_age = 300
        @max_entries = 20
        @max_size = 2048
      end

      def clear(_options = nil)
        @clear_calls += 1
      end

      def cleanup(_options = nil)
        @cleanup_calls += 1
      end

      def with_each_connection
        @connection_passes += 1
        yield
      end
    end
  end
  let(:cache_store) { store_class.new }

  before do
    stub_const("SolidCache", Module.new)
    stub_const("SolidCache::Store", store_class)
    stub_const("SolidCache::Entry", entry_class)
    allow(Rails).to receive(:cache).and_return(cache_store)
    allow(Rails).to receive(:logger).and_return(logger)
    SolidObserver.config.observe_cache = true
  end

  after { SolidObserver.reset_configuration! }

  describe ".available?" do
    it "returns true for an enabled SolidCache store" do
      expect(described_class.available?).to be(true)
    end

    it "returns false when cache observation is disabled" do
      SolidObserver.config.observe_cache = false

      expect(described_class.available?).to be(false)
    end

    it "returns false for a non-SolidCache store" do
      allow(Rails).to receive(:cache).and_return(ActiveSupport::Cache.lookup_store(:memory_store))

      expect(described_class.available?).to be(false)
    end
  end

  describe ".clear" do
    it "clears the current SolidCache store" do
      result = described_class.clear

      expect(result).to eq(
        ok: true,
        message: described_class.message(:clear, :success)
      )
      expect(cache_store.clear_calls).to eq(1)
    end

    it "returns the unavailable copy when controls cannot run" do
      SolidObserver.config.observe_cache = false

      expect(described_class.clear).to eq(
        ok: false,
        message: described_class.unavailable_message
      )
    end

    it "logs and sanitizes clear failures" do
      allow(cache_store).to receive(:clear).and_raise(ActiveRecord::StatementInvalid.new("bad sql"))

      result = described_class.clear

      expect(result).to eq(
        ok: false,
        message: described_class.message(:clear, :failure)
      )
      expect(logger).to have_received(:warn).with(
        "[SolidObserver] Cache clear failed: ActiveRecord::StatementInvalid"
      )
    end
  end

  describe ".prune" do
    it "uses the public cleanup API when available" do
      result = described_class.prune

      expect(result).to eq(
        ok: true,
        message: described_class.message(:prune, :success)
      )
      expect(cache_store.cleanup_calls).to eq(1)
      expect(entry_class.expire_calls).to be_nil
    end

    it "falls back to SolidCache expiry when cleanup is unsupported" do
      allow(cache_store).to receive(:cleanup).and_raise(NotImplementedError)

      result = described_class.prune

      expect(result).to eq(
        ok: true,
        message: described_class.message(:prune, :success)
      )
      expect(cache_store.connection_passes).to eq(1)
      expect(entry_class.expire_calls).to eq([
        {
          args: [12],
          kwargs: {max_age: 300, max_entries: 20, max_size: 2048}
        }
      ])
    end

    it "returns the failure copy when no prune fallback is available" do
      allow(cache_store).to receive(:cleanup).and_raise(NotImplementedError)
      hide_const("SolidCache::Entry")

      result = described_class.prune

      expect(result).to eq(
        ok: false,
        message: described_class.message(:prune, :failure)
      )
      expect(logger).to have_received(:warn).with(
        "[SolidObserver] Cache prune failed: RuntimeError"
      )
    end
  end
end
