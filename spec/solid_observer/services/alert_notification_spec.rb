# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::AlertNotification do
  before(:all) do
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
    SolidObserver::AlertHistory.reset_column_information
    SolidObserver::AlertHistory.define_attribute_methods
  end

  after { SolidObserver.reset_configuration! }

  let(:alert_history) do
    instance_double(
      SolidObserver::AlertHistory,
      payload: {"rule_name" => "High error rate"},
      metric_value: 0.42,
      triggered_at: Time.current,
      state: "triggered"
    )
  end

  def stub_channel(klass, &block)
    channel = instance_double(klass)
    if block
      allow(channel).to receive(:deliver, &block)
    else
      allow(channel).to receive(:deliver)
    end
    allow(klass).to receive(:new).and_return(channel)
    channel
  end

  describe ".call" do
    it "returns an empty array when no channel is configured" do
      expect(described_class.call(alert_history: alert_history)).to eq([])
    end

    it "delivers only to channels with config present and returns a success DeliveryResult per channel" do
      SolidObserver.config.slack_webhook_url = "https://hooks.slack.com/services/x"
      slack = stub_channel(SolidObserver::Channels::Slack)

      results = described_class.call(alert_history: alert_history)

      expect(slack).to have_received(:deliver).with(alert_history, kind_of(Hash))
      expect(results.map(&:channel)).to eq([:slack])
      expect(results.first).to have_attributes(status: :success, error_class: nil, error_message: nil)
      expect(results.first.attempted_at).to be_a(Time)
    end

    it "captures a channel failure into a failed DeliveryResult instead of raising" do
      SolidObserver.config.webhook_endpoint_url = "https://example.com/hooks"
      stub_channel(SolidObserver::Channels::Webhook) { raise Net::HTTPClientException.new("400", nil) }

      results = described_class.call(alert_history: alert_history)

      expect(results.first).to have_attributes(
        channel: :webhook,
        status: :failed,
        error_class: "Net::HTTPClientException",
        error_message: "400"
      )
    end

    it "delivers to every configured channel independently" do
      SolidObserver.config.slack_webhook_url = "https://hooks.slack.com/services/x"
      SolidObserver.config.email_recipients = ["a@example.com"]
      SolidObserver.config.webhook_endpoint_url = "https://example.com/hooks"
      stub_channel(SolidObserver::Channels::Slack)
      stub_channel(SolidObserver::Channels::Email)
      stub_channel(SolidObserver::Channels::Webhook)

      results = described_class.call(alert_history: alert_history)

      expect(results.map(&:channel)).to contain_exactly(:slack, :email, :webhook)
    end

    it "honors an explicit channels: override regardless of config presence" do
      email = stub_channel(SolidObserver::Channels::Email)

      results = described_class.call(alert_history: alert_history, channels: [:email])

      expect(email).to have_received(:deliver)
      expect(results.map(&:channel)).to eq([:email])
    end

    it "passes event_type through to the payload builder" do
      SolidObserver.config.slack_webhook_url = "https://hooks.slack.com/services/x"
      slack = stub_channel(SolidObserver::Channels::Slack)

      described_class.call(alert_history: alert_history, event_type: "resolved")

      expect(slack).to have_received(:deliver) do |_history, payload|
        expect(payload[:event_type]).to eq("resolved")
      end
    end
  end

  describe "DeliveryResult" do
    it "exposes the documented struct fields" do
      expect(described_class::DeliveryResult.members).to eq(%i[channel status error_class error_message attempted_at])
    end
  end
end
