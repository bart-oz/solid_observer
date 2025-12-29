# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Configuration do
  it "sets sensible defaults" do
    config = described_class.new

    expect(config.sampling_rate).to eq(1.0)
    expect(config.buffer_size).to eq(1000)
    expect(config.observe_queue).to be true
    expect(config.max_db_size).to eq(1.gigabyte)
    expect(config.warning_threshold).to eq(0.8)
  end

  it "disables UI in production" do
    allow_any_instance_of(described_class).to receive(:production?).and_return(true)
    expect(described_class.new.ui_enabled).to be false
  end

  it "enables UI outside production" do
    allow_any_instance_of(described_class).to receive(:production?).and_return(false)
    expect(described_class.new.ui_enabled).to be true
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
