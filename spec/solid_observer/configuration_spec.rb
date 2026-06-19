# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Configuration do
  after { SolidObserver.reset_configuration! }

  it "sets sensible defaults" do
    config = described_class.new

    expect(config.sampling_rate).to eq(1.0)
    expect(config.cable_sampling_rate).to eq(0.1)
    expect(config.buffer_size).to eq(1000)
    expect(config.max_buffer_size).to eq(10_000)
    expect(config.buffer_overflow_strategy).to eq(:drop_old)
    expect(config.filter_cache_ttl).to eq(1.minute)
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

  describe "component helpers" do
    it "reports queue enabled by default when SolidQueue is available" do
      stub_const("SolidQueue", Module.new)
      config = described_class.new

      expect(config.solid_queue_available?).to be(true)
      expect(config.solid_queue_enabled?).to be(true)
    end

    it "reports cache disabled by default when SolidCache is absent" do
      hide_const("SolidCache")
      config = described_class.new

      expect(config.solid_cache_available?).to be(false)
      expect(config.solid_cache_enabled?).to be(false)
    end

    it "enables cache only when observe_cache and SolidCache are both present" do
      stub_const("SolidCache", Module.new)
      config = described_class.new
      config.observe_cache = true

      expect(config.solid_cache_available?).to be(true)
      expect(config.solid_cache_enabled?).to be(true)
    end

    it "reports cable disabled by default when SolidCable is absent" do
      hide_const("SolidCable")
      config = described_class.new

      expect(config.solid_cable_available?).to be(false)
      expect(config.solid_cable_enabled?).to be(false)
    end

    it "enables cable only when observe_cable and SolidCable are both present" do
      stub_const("SolidCable", Module.new)
      config = described_class.new
      config.observe_cable = true

      expect(config.solid_cable_available?).to be(true)
      expect(config.solid_cable_enabled?).to be(true)
    end
  end

  describe "#max_buffer_size" do
    it "accepts positive integers greater than or equal to buffer_size" do
      config = described_class.new
      config.buffer_size = 1000
      config.max_buffer_size = 5000

      expect(config.max_buffer_size).to eq(5000)
    end

    it "raises when value is not a positive integer" do
      config = described_class.new

      expect { config.max_buffer_size = 0 }.to raise_error(
        ArgumentError, "max_buffer_size must be a positive integer"
      )
    end

    it "raises when value is smaller than buffer_size" do
      config = described_class.new
      config.buffer_size = 300

      expect { config.max_buffer_size = 299 }.to raise_error(
        ArgumentError, "max_buffer_size must be >= buffer_size"
      )
    end
  end

  describe "#buffer_size" do
    it "raises when value is greater than max_buffer_size" do
      config = described_class.new
      config.max_buffer_size = 2000

      expect { config.buffer_size = 2001 }.to raise_error(
        ArgumentError, "buffer_size must be <= max_buffer_size"
      )
    end
  end

  describe "#buffer_overflow_strategy" do
    it "accepts :drop_old" do
      config = described_class.new
      config.buffer_overflow_strategy = :drop_old

      expect(config.buffer_overflow_strategy).to eq(:drop_old)
    end

    it "accepts :drop_new" do
      config = described_class.new
      config.buffer_overflow_strategy = :drop_new

      expect(config.buffer_overflow_strategy).to eq(:drop_new)
    end

    it "accepts string values" do
      config = described_class.new
      config.buffer_overflow_strategy = "drop_new"

      expect(config.buffer_overflow_strategy).to eq(:drop_new)
    end

    it "raises for unsupported values" do
      config = described_class.new

      expect { config.buffer_overflow_strategy = :invalid }.to raise_error(
        ArgumentError, "buffer_overflow_strategy must be :drop_old or :drop_new"
      )
    end
  end

  describe "cable stability thresholds" do
    it "sets sensible defaults" do
      config = described_class.new

      expect(config.cable_rejection_threshold).to eq(0.05)
      expect(config.cable_backlog_threshold).to eq(0.10)
      expect(config.cable_error_threshold).to eq(0.0)
    end

    describe "#cable_rejection_threshold=" do
      it "accepts values between 0.0 and 1.0" do
        config = described_class.new
        config.cable_rejection_threshold = 0.03

        expect(config.cable_rejection_threshold).to eq(0.03)
      end

      it "rejects values below 0.0" do
        config = described_class.new

        expect { config.cable_rejection_threshold = -0.1 }.to raise_error(
          ArgumentError, "cable_rejection_threshold must be a number between 0.0 and 1.0"
        )
      end

      it "rejects values above 1.0" do
        config = described_class.new

        expect { config.cable_rejection_threshold = 1.1 }.to raise_error(
          ArgumentError, "cable_rejection_threshold must be a number between 0.0 and 1.0"
        )
      end
    end

    describe "#cable_backlog_threshold=" do
      it "accepts values between 0.0 and 1.0" do
        config = described_class.new
        config.cable_backlog_threshold = 0.2

        expect(config.cable_backlog_threshold).to eq(0.2)
      end

      it "rejects values above 1.0" do
        config = described_class.new

        expect { config.cable_backlog_threshold = 1.5 }.to raise_error(
          ArgumentError, "cable_backlog_threshold must be a number between 0.0 and 1.0"
        )
      end
    end

    describe "#cable_error_threshold=" do
      it "accepts non-negative numeric values" do
        config = described_class.new
        config.cable_error_threshold = 5

        expect(config.cable_error_threshold).to eq(5)
      end

      it "rejects negative values" do
        config = described_class.new

        expect { config.cable_error_threshold = -1 }.to raise_error(
          ArgumentError, "cable_error_threshold must be a non-negative number"
        )
      end

      it "rejects non-numeric values" do
        config = described_class.new

        expect { config.cable_error_threshold = "none" }.to raise_error(
          ArgumentError, "cable_error_threshold must be a non-negative number"
        )
      end
    end
  end

  describe "#cable_sampling_rate=" do
    it "accepts values between 0.0 and 1.0" do
      config = described_class.new
      config.cable_sampling_rate = 0.5

      expect(config.cable_sampling_rate).to eq(0.5)
    end

    it "rejects values below 0.0" do
      config = described_class.new

      expect { config.cable_sampling_rate = -0.1 }.to raise_error(
        ArgumentError, "cable_sampling_rate must be a number between 0.0 and 1.0"
      )
    end

    it "rejects values above 1.0" do
      config = described_class.new

      expect { config.cable_sampling_rate = 1.1 }.to raise_error(
        ArgumentError, "cable_sampling_rate must be a number between 0.0 and 1.0"
      )
    end

    it "rejects non-numeric values" do
      config = described_class.new

      expect { config.cable_sampling_rate = "half" }.to raise_error(
        ArgumentError, "cable_sampling_rate must be a number between 0.0 and 1.0"
      )
    end
  end

  describe "#filter_cache_ttl=" do
    it "accepts positive numeric duration values" do
      config = described_class.new
      config.filter_cache_ttl = 5.minutes
      expect(config.filter_cache_ttl).to eq(5.minutes)
    end

    it "accepts positive numeric seconds" do
      config = described_class.new
      config.filter_cache_ttl = 30
      expect(config.filter_cache_ttl).to eq(30)
    end

    it "rejects zero" do
      config = described_class.new
      expect { config.filter_cache_ttl = 0 }.to raise_error(
        ArgumentError, "filter_cache_ttl must be a positive number"
      )
    end

    it "rejects negative values" do
      config = described_class.new
      expect { config.filter_cache_ttl = -1 }.to raise_error(
        ArgumentError, "filter_cache_ttl must be a positive number"
      )
    end

    it "rejects strings" do
      config = described_class.new
      expect { config.filter_cache_ttl = "abc" }.to raise_error(
        ArgumentError, "filter_cache_ttl must be a positive number"
      )
    end

    it "rejects nil" do
      config = described_class.new
      expect { config.filter_cache_ttl = nil }.to raise_error(
        ArgumentError, "filter_cache_ttl must be a positive number"
      )
    end
  end

  it "disables UI in production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))

    expect(described_class.new.ui_enabled).to be false
  end

  it "enables UI outside production" do
    allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("test"))

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
