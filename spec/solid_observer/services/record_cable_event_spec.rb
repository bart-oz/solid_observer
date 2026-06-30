# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::RecordCableEvent do
  let(:buffer) { instance_double(SolidObserver::CableEventBuffer, push: nil) }
  let(:broadcast_payload) { {broadcasting: "chat:1"} }
  let(:broadcast_event) do
    ActiveSupport::Notifications::Event.new(
      "broadcast.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      broadcast_payload
    )
  end

  before do
    SolidObserver.reset_configuration!
    SolidObserver::CableMetricBuffer.instance.clear
    SolidObserver::CableMetricBuffer.instance.shutdown
  end

  after do
    SolidObserver::CableMetricBuffer.instance.clear
    SolidObserver::CableMetricBuffer.instance.shutdown
    SolidObserver.reset_configuration!
  end

  it "stores a broadcasting digest, sanitized metadata, and a correlation_id for sampled broadcasts" do
    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)

    described_class.call(event: broadcast_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      event_type: "broadcast",
      correlation_id: a_string_matching(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/),
      channel_class: nil,
      broadcasting_digest: Digest::SHA256.hexdigest("chat:1"),
      duration: be > 0,
      error_class: nil,
      error_message: nil,
      metadata: satisfy { |json| JSON.parse(json).keys.none? { |key| %w[broadcasting message data identifier].include?(key) } }
    ))
  end

  it "does not persist raw broadcasting names, messages, data, or job arguments" do
    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)

    described_class.call(event: broadcast_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(satisfy { |data|
      data.keys.none? { |key| %i[broadcasting message data arguments args].include?(key) }
    })
  end

  it "records metrics even when raw event is not sampled" do
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(0.0)
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call)

    described_class.call(event: broadcast_event, buffer: buffer)

    expect(SolidObserver::Services::RecordCableMetric).to have_received(:call).with(event: broadcast_event)
    expect(buffer).not_to have_received(:push)
  end

  it "stores broadcast errors even when not sampled" do
    error_event = ActiveSupport::Notifications::Event.new(
      "broadcast.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {broadcasting: "chat:1", exception_object: StandardError.new("Broadcast failed")}
    )

    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(0.0)

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      error_class: "StandardError",
      error_message: "Broadcast failed"
    ))
  end

  it "always stores subscription rejections" do
    rejection_event = ActiveSupport::Notifications::Event.new(
      "transmit_subscription_rejection.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel_class: "ChatChannel"}
    )

    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(0.0)

    described_class.call(event: rejection_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      event_type: "transmit_subscription_rejection",
      channel_class: "ChatChannel"
    ))
  end

  it "does not store raw rows for transmit events but records metrics" do
    transmit_event = ActiveSupport::Notifications::Event.new(
      "transmit.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel: Class.new { def self.name = "ChatChannel" }, message: "hello"}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call)

    described_class.call(event: transmit_event, buffer: buffer)

    expect(SolidObserver::Services::RecordCableMetric).to have_received(:call).with(event: transmit_event)
    expect(buffer).not_to have_received(:push)
  end

  it "does not store raw rows for confirmation events but records metrics" do
    confirmation_event = ActiveSupport::Notifications::Event.new(
      "transmit_subscription_confirmation.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel_class: "ChatChannel"}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call)

    described_class.call(event: confirmation_event, buffer: buffer)

    expect(SolidObserver::Services::RecordCableMetric).to have_received(:call).with(event: confirmation_event)
    expect(buffer).not_to have_received(:push)
  end

  it "does not store raw rows for perform_action events but records metrics" do
    perform_event = ActiveSupport::Notifications::Event.new(
      "perform_action.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel_class: "ChatChannel", action: "speak", data: {message: "hi"}}
    )

    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call)

    described_class.call(event: perform_event, buffer: buffer)

    expect(SolidObserver::Services::RecordCableMetric).to have_received(:call).with(event: perform_event)
    expect(buffer).not_to have_received(:push)
  end

  it "extracts channel_class from channel object when channel_class payload key is absent" do
    chat_channel_class = Class.new do
      def self.name = "ChatChannel"
    end
    rejection_event = ActiveSupport::Notifications::Event.new(
      "transmit_subscription_rejection.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel: chat_channel_class.new}
    )

    stub_channel_class_event(rejection_event)

    expect(buffer).to have_received(:push).with(hash_including(channel_class: "ChatChannel"))
  end

  it "extracts channel_class from payload when present" do
    rejection_event = ActiveSupport::Notifications::Event.new(
      "transmit_subscription_rejection.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel_class: "ChatChannel"}
    )

    stub_channel_class_event(rejection_event)

    expect(buffer).to have_received(:push).with(hash_including(channel_class: "ChatChannel"))
  end

  it "records exception_object details on stored events" do
    error_event = ActiveSupport::Notifications::Event.new(
      "transmit_subscription_rejection.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {channel_class: "ChatChannel", exception_object: StandardError.new("Rejected")}
    )

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      error_class: "StandardError",
      error_message: "Rejected"
    ))
  end

  it "records explicit exception payload details on stored events" do
    error_event = ActiveSupport::Notifications::Event.new(
      "broadcast.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {broadcasting: "chat:1", exception: ["StandardError", "Broadcast timeout"]}
    )

    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(0.0)

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:push).with(hash_including(
      error_class: "StandardError",
      error_message: "Broadcast timeout"
    ))
  end

  it "emits no solid_observer_cable_metrics SQL on the notification callback path" do
    SolidObserver.config.buffer_size = 1000
    allow(Kernel).to receive(:rand).and_return(0.9)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(0.0)

    sql = capture_sql do
      described_class.call(event: broadcast_event, buffer: buffer)
    end

    expect(sql.grep(/solid_observer_cable_metrics/i)).to be_empty
    expect(SolidObserver::CableMetricBuffer.instance.size).to eq(1)
    expect(buffer).not_to have_received(:push)
  end

  it "re-raises NameError wiring failures" do
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call).and_raise(
      NameError.new("uninitialized constant SolidObserver::Services::RecordCableMetric")
    )

    expect {
      described_class.call(event: broadcast_event, buffer: buffer)
    }.to raise_error(NameError, /RecordCableMetric/)

    expect(buffer).not_to have_received(:push)
  end

  it "logs and swallows ordinary StandardError failures" do
    logger = instance_double(Logger, warn: nil)

    allow(Rails).to receive(:logger).and_return(logger)
    allow(SolidObserver::Services::RecordCableMetric).to receive(:call).and_raise(
      ActiveRecord::StatementInvalid.new("missing table")
    )

    expect {
      described_class.call(event: broadcast_event, buffer: buffer)
    }.not_to raise_error

    expect(logger).to have_received(:warn).with(
      "[SolidObserver] Cable event recording failed: missing table"
    )
    expect(buffer).not_to have_received(:push)
  end

  def stub_channel_class_event(event)
    allow(Kernel).to receive(:rand).and_return(0.0)
    allow(SolidObserver.config).to receive(:cable_sampling_rate).and_return(1.0)

    described_class.call(event: event, buffer: buffer)
  end

  def capture_sql
    statements = []
    subscriber = ActiveSupport::Notifications.subscribe("sql.active_record") do |_name, _started, _finished, _id, sql_payload|
      statements << sql_payload[:sql]
    end

    yield
    statements
  ensure
    ActiveSupport::Notifications.unsubscribe(subscriber) if subscriber
  end
end
