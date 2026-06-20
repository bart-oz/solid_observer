# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/solid_observer/services/cable_operations"

RSpec.describe SolidObserver::Services::CableOperations do
  let(:logger) { instance_double(Logger, warn: nil) }
  let(:trimmable_relation) { double(delete_all: 3) }
  let(:message_class) do
    Class.new do
      class << self
        attr_accessor :trimmable_relation

        def trimmable
          trimmable_relation
        end
      end
    end
  end

  before do
    stub_const("SolidCable", Module.new)
    stub_const("SolidCable::Message", message_class)
    message_class.trimmable_relation = trimmable_relation
    allow(Rails).to receive(:logger).and_return(logger)
    SolidObserver.config.observe_cable = true
  end

  after { SolidObserver.reset_configuration! }

  describe ".available?" do
    it "returns true when cable observation is enabled and SolidCable::Message is present" do
      expect(described_class.available?).to be(true)
    end

    it "returns false when cable observation is disabled" do
      SolidObserver.config.observe_cable = false

      expect(described_class.available?).to be(false)
    end

    it "returns false when SolidCable::Message is not defined" do
      hide_const("SolidCable::Message")

      expect(described_class.available?).to be(false)
    end
  end

  describe ".trim" do
    it "trims expired/trimmable messages using the fallback delete path" do
      expect(trimmable_relation).to receive(:delete_all).and_return(3)

      result = described_class.trim

      expect(result).to eq(
        ok: true,
        message: described_class.message(:trim, :success)
      )
    end

    it "prefers SolidCable::TrimJob.perform_now when defined" do
      trim_job = Class.new do
        class << self
          attr_accessor :performed

          def perform_now
            @performed = true
          end
        end
      end
      stub_const("SolidCable::TrimJob", trim_job)

      result = described_class.trim

      expect(trim_job.performed).to be(true)
      expect(result).to eq(
        ok: true,
        message: described_class.message(:trim, :success)
      )
      expect(trimmable_relation).not_to have_received(:delete_all)
    end

    it "returns the unavailable copy when controls cannot run" do
      SolidObserver.config.observe_cable = false

      result = described_class.trim

      expect(result).to eq(
        ok: false,
        message: described_class.unavailable_message
      )
      expect(trimmable_relation).not_to have_received(:delete_all)
    end

    it "logs and sanitizes trim failures without exposing adapter details" do
      allow(trimmable_relation).to receive(:delete_all).and_raise(
        ActiveRecord::StatementInvalid.new("bad cable sql")
      )

      result = described_class.trim

      expect(result).to eq(
        ok: false,
        message: described_class.message(:trim, :failure)
      )
      expect(logger).to have_received(:warn).with(
        "[SolidObserver] Cable trim failed: ActiveRecord::StatementInvalid"
      )
    end
  end
end
