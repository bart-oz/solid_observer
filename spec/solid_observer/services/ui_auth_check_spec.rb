# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::UiAuthCheck do
  let(:logger) { instance_double(Logger, warn: nil) }
  let(:config) { SolidObserver::Configuration.new }

  describe ".call" do
    context "when ui_enabled is false" do
      before { config.ui_enabled = false }

      it "does not log a warning even with no credentials set" do
        expect(logger).not_to receive(:warn)
        described_class.call(config: config, logger: logger)
      end
    end

    context "when both credentials are set" do
      before do
        config.ui_enabled = true
        config.ui_username = "admin"
        config.ui_password = "secret"
      end

      it "does not log a warning" do
        expect(logger).not_to receive(:warn)
        described_class.call(config: config, logger: logger)
      end
    end

    context "when neither credential is set" do
      before do
        config.ui_enabled = true
        config.ui_username = nil
        config.ui_password = nil
      end

      it "logs the no-authentication warning" do
        expect(logger).to receive(:warn).with(
          /WARNING: UI is enabled with no authentication configured/
        )
        described_class.call(config: config, logger: logger)
      end
    end

    context "when only ui_username is set" do
      before do
        config.ui_enabled = true
        config.ui_username = "admin"
        config.ui_password = nil
      end

      it "logs a misconfiguration warning naming the missing password" do
        expect(logger).to receive(:warn).with(
          /UI authentication is misconfigured — ui_username is set but ui_password is missing\/nil/
        )
        described_class.call(config: config, logger: logger)
      end
    end

    context "when only ui_password is set" do
      before do
        config.ui_enabled = true
        config.ui_username = nil
        config.ui_password = "secret"
      end

      it "logs a misconfiguration warning naming the missing username" do
        expect(logger).to receive(:warn).with(
          /UI authentication is misconfigured — ui_password is set but ui_username is missing\/nil/
        )
        described_class.call(config: config, logger: logger)
      end
    end

    context "when an empty string is set as a credential" do
      before do
        config.ui_enabled = true
        config.ui_username = "admin"
        config.ui_password = ""
      end

      it "treats blank as missing and warns" do
        expect(logger).to receive(:warn).with(
          /UI authentication is misconfigured — ui_username is set but ui_password is missing\/nil/
        )
        described_class.call(config: config, logger: logger)
      end
    end
  end

  describe ".call default logger" do
    it "defaults to Rails.logger when no logger is given" do
      config.ui_enabled = true
      allow(Rails).to receive(:logger).and_return(logger)
      expect(logger).to receive(:warn)
      described_class.call(config: config)
    end
  end
end
