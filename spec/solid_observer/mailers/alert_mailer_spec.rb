# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::AlertMailer do
  before(:all) do
    engine_views = SolidObserver::Engine.root.join("app/views").to_s
    described_class.prepend_view_path(engine_views) unless described_class.view_paths.map(&:to_s).include?(engine_views)

    connection = SolidObserver::AlertHistory.connection
    unless connection.table_exists?(:solid_observer_alert_histories)
      connection.create_table :solid_observer_alert_histories do |t|
        t.bigint :alert_rule_id, null: false
        t.datetime :triggered_at, null: false
        t.datetime :resolved_at
        t.float :metric_value, null: false
        t.string :state, null: false, limit: 16
        t.text :payload
        t.timestamps
      end
    end
    # Regenerate attribute methods even if another spec file already created
    # this table — a `force: true` recreate elsewhere leaves them stale.
    SolidObserver::AlertHistory.reset_column_information
    SolidObserver::AlertHistory.define_attribute_methods
  end

  after { SolidObserver.reset_configuration! }

  let(:alert_history) do
    instance_double(
      SolidObserver::AlertHistory,
      payload: {"rule_name" => "High error rate", "severity" => "critical", "metric_type" => "error_rate", "environment" => "production"},
      metric_value: 0.42,
      triggered_at: Time.current,
      state: "triggered"
    )
  end

  let(:payload) { SolidObserver::Services::AlertPayload.call(alert_history: alert_history) }

  describe "#notification_email" do
    subject(:mail) { described_class.notification_email(alert_history, payload, ["oncall@example.com"]).message }

    it "addresses the given recipients" do
      expect(mail.to).to eq(["oncall@example.com"])
    end

    it "sets a subject naming the event type and rule" do
      expect(mail.subject).to eq("[SolidObserver] triggered — High error rate")
    end

    it "renders HTML and text parts with rule details, metric value, status, and the deep link" do
      %i[html_part text_part].each do |part|
        body = mail.public_send(part).body.to_s
        expect(body).to include("High error rate", "critical", "error_rate = 0.42", "production", "triggered")
      end
    end
  end

  context "when notification_base_url is unset" do
    it "falls back to a relative deep link with an ActiveSupport::Logger warning" do
      logger = instance_double(Logger, warn: nil)
      allow(Rails).to receive(:logger).and_return(logger)

      mail = described_class.notification_email(alert_history, payload, ["oncall@example.com"]).message

      expect(logger).to have_received(:warn).with(/notification_base_url/)
      expect(mail.html_part.body.to_s).to include('href="/solid_observer"')
      expect(mail.text_part.body.to_s).to include("/solid_observer")
    end
  end

  context "when notification_base_url is configured" do
    before { SolidObserver.config.notification_base_url = "https://app.example.com" }

    it "links to the absolute deep link URL" do
      mail = described_class.notification_email(alert_history, payload, ["oncall@example.com"]).message

      expect(mail.html_part.body.to_s).to include('href="https://app.example.com/solid_observer"')
    end
  end
end
