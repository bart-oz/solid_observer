# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Configuration do
  after { SolidObserver.reset_configuration! }

  it "sets sensible defaults" do
    config = described_class.new

    expect(config.sampling_rate).to eq(1.0)
    expect(config.buffer_size).to eq(1000)
    expect(config.observe_queue).to be true
    expect(config.max_db_size).to eq(1.gigabyte)
    expect(config.warning_threshold).to eq(0.8)
    expect(config.storage_mode).to eq(:persistence)
  end

  describe "#storage_mode" do
    it "defaults to :persistence" do
      expect(described_class.new.storage_mode).to eq(:persistence)
    end

    it "accepts :realtime" do
      config = described_class.new
      config.storage_mode = :realtime
      expect(config.storage_mode).to eq(:realtime)
    end

    it "accepts :persistence" do
      config = described_class.new
      config.storage_mode = :persistence
      expect(config.storage_mode).to eq(:persistence)
    end

    it "accepts string values" do
      config = described_class.new
      config.storage_mode = "realtime"
      expect(config.storage_mode).to eq(:realtime)
    end

    it "raises ArgumentError for invalid values" do
      config = described_class.new
      expect { config.storage_mode = :invalid }.to raise_error(
        ArgumentError, "storage_mode must be :persistence or :realtime"
      )
    end
  end

  describe "#persistence_mode?" do
    it "returns true when storage_mode is :persistence" do
      config = described_class.new
      expect(config.persistence_mode?).to be true
    end

    it "returns false when storage_mode is :realtime" do
      config = described_class.new
      config.storage_mode = :realtime
      expect(config.persistence_mode?).to be false
    end
  end

  describe "#realtime_mode?" do
    it "returns true when storage_mode is :realtime" do
      config = described_class.new
      config.storage_mode = :realtime
      expect(config.realtime_mode?).to be true
    end

    it "returns false when storage_mode is :persistence" do
      config = described_class.new
      expect(config.realtime_mode?).to be false
    end
  end

  it "disables UI in production" do
    allow_any_instance_of(described_class).to receive(:production?).and_return(true)
    expect(described_class.new.ui_enabled).to be false
  end

  it "enables UI outside production" do
    allow_any_instance_of(described_class).to receive(:production?).and_return(false)
    expect(described_class.new.ui_enabled).to be true
  end

  it "allows custom correlation_id_generator" do
    generator = -> { "custom-id-123" }

    SolidObserver.configure do |config|
      config.correlation_id_generator = generator
    end

    expect(SolidObserver.config.correlation_id_generator).to eq(generator)
    expect(SolidObserver.config.correlation_id_generator.call).to eq("custom-id-123")
  end

  it "defaults correlation_id_generator to nil" do
    expect(SolidObserver.config.correlation_id_generator).to be_nil
  end
end

RSpec.describe SolidObserver do
  after { SolidObserver.reset_configuration! }

  it "allows configuration via block" do
    SolidObserver.configure do |config|
      config.sampling_rate = 0.5
      config.ui_enabled = false
    end

    expect(SolidObserver.config.sampling_rate).to eq(0.5)
    expect(SolidObserver.config.ui_enabled).to be false
  end

  it "returns singleton configuration" do
    expect(SolidObserver.configuration).to be(SolidObserver.configuration)
  end

  it "resets configuration to defaults" do
    SolidObserver.config.sampling_rate = 0.5
    SolidObserver.reset_configuration!
    expect(SolidObserver.config.sampling_rate).to eq(1.0)
  end
end
