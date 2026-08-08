# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::NotificationDeliveryJob do
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

  around do |example|
    original_adapter = described_class.queue_adapter
    described_class.queue_adapter = :test
    example.run
    described_class.queue_adapter = original_adapter
  end

  let(:alert_history) { instance_double(SolidObserver::AlertHistory, payload: {}, metric_value: 1.0, triggered_at: Time.current, state: "triggered") }

  before { allow(SolidObserver::AlertHistory).to receive(:find).with(42).and_return(alert_history) }

  def success_result(channel: :slack)
    SolidObserver::Services::AlertNotification::DeliveryResult.new(channel: channel, status: :success, error_class: nil, error_message: nil, attempted_at: Time.current)
  end

  def failed_result(error_class, channel: :webhook, error_message: "boom")
    SolidObserver::Services::AlertNotification::DeliveryResult.new(channel: channel, status: :failed, error_class: error_class, error_message: error_message, attempted_at: Time.current)
  end

  it "queues on the default queue" do
    expect(described_class.new.queue_name).to eq("default")
  end

  it "registers the exact retryable and discardable exception taxonomy" do
    handled = described_class.rescue_handlers.map(&:first)

    expect(handled).to eq(%w[
      Net::OpenTimeout Net::ReadTimeout Net::WriteTimeout
      Errno::ECONNREFUSED Errno::ECONNRESET SocketError Net::HTTPFatalError
      Net::HTTPClientException
    ])
  end

  it "finds the AlertHistory and routes it through Services::AlertNotification" do
    expect(SolidObserver::Services::AlertNotification).to receive(:call)
      .with(alert_history: alert_history, event_type: "resolved")
      .and_return([success_result])

    described_class.perform_now(42, "resolved")
  end

  it "does not raise or retry when every channel succeeds" do
    allow(SolidObserver::Services::AlertNotification).to receive(:call).and_return([success_result])

    expect { described_class.perform_now(42) }.not_to raise_error
    expect(described_class.queue_adapter.enqueued_jobs).to be_empty
  end

  it "retries the job when a channel fails with a transient/5xx error" do
    allow(SolidObserver::Services::AlertNotification).to receive(:call).and_return([failed_result("Net::HTTPFatalError")])

    expect { described_class.perform_now(42) }.not_to raise_error
    expect(described_class.queue_adapter.enqueued_jobs.size).to eq(1)
  end

  it "discards the job with a warning log when a channel fails with a 4xx client error" do
    allow(SolidObserver::Services::AlertNotification).to receive(:call).and_return([failed_result("Net::HTTPClientException", channel: :slack, error_message: "invalid_token")])
    logger = instance_double(Logger, warn: nil)
    allow(Rails).to receive(:logger).and_return(logger)

    expect { described_class.perform_now(42) }.not_to raise_error

    expect(logger).to have_received(:warn).with(/NotificationDeliveryJob discarded: Net::HTTPClientException: invalid_token/)
    expect(described_class.queue_adapter.enqueued_jobs).to be_empty
  end

  it "raises (fails loudly) for an error class outside the retry/discard taxonomy" do
    allow(SolidObserver::Services::AlertNotification).to receive(:call).and_return([failed_result("RuntimeError", error_message: "unexpected")])

    expect { described_class.perform_now(42) }.to raise_error(RuntimeError, "unexpected")
  end
end
