# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Channels::Email do
  after { SolidObserver.reset_configuration! }

  let(:alert_history) { double("AlertHistory") }
  let(:payload) { {rule_name: "High error rate", event_type: "triggered"} }
  let(:mail_message) { instance_double(ActionMailer::MessageDelivery, deliver_now: true) }

  before { SolidObserver.config.email_recipients = ["oncall@example.com"] }

  it "delivers the AlertMailer notification email synchronously to the configured recipients" do
    expect(SolidObserver::AlertMailer).to receive(:notification_email)
      .with(alert_history, payload, ["oncall@example.com"])
      .and_return(mail_message)

    described_class.new.deliver(alert_history, payload)

    expect(mail_message).to have_received(:deliver_now)
  end
end
