# frozen_string_literal: true

require "spec_helper"
require "time"

RSpec.describe SolidObserver::Services::RecordCableMetric do
  let(:buffer) { instance_double(SolidObserver::CableMetricBuffer, increment: nil) }

  it "buffers a metric in a 1-minute bucket without writing to the database" do
    travel_to(Time.parse("2026-06-01 12:34:45 UTC")) do
      described_class.call(
        event: ActiveSupport::Notifications::Event.new("broadcast.action_cable", Time.current, Time.current + 0.01, "id", {}),
        buffer: buffer
      )
    end

    expect(buffer).to have_received(:increment).with(
      hash_including(
        period_start: Time.parse("2026-06-01 12:34:00 UTC"),
        broadcasts_count: 1,
        transmissions_count: 0,
        confirmations_count: 0,
        rejections_count: 0,
        perform_actions_count: 0,
        errors_count: 0
      )
    )
  end

  it "maps transmit events to transmissions_count" do
    described_class.call(
      event: ActiveSupport::Notifications::Event.new("transmit.action_cable", Time.current, Time.current + 0.01, "id", {}),
      buffer: buffer
    )

    expect(buffer).to have_received(:increment).with(hash_including(transmissions_count: 1))
  end

  it "maps confirmation events to confirmations_count" do
    described_class.call(
      event: ActiveSupport::Notifications::Event.new("transmit_subscription_confirmation.action_cable", Time.current, Time.current + 0.01, "id", {}),
      buffer: buffer
    )

    expect(buffer).to have_received(:increment).with(hash_including(confirmations_count: 1))
  end

  it "maps rejection events to rejections_count" do
    described_class.call(
      event: ActiveSupport::Notifications::Event.new("transmit_subscription_rejection.action_cable", Time.current, Time.current + 0.01, "id", {}),
      buffer: buffer
    )

    expect(buffer).to have_received(:increment).with(hash_including(rejections_count: 1))
  end

  it "maps perform_action events to perform_actions_count" do
    described_class.call(
      event: ActiveSupport::Notifications::Event.new("perform_action.action_cable", Time.current, Time.current + 0.01, "id", {}),
      buffer: buffer
    )

    expect(buffer).to have_received(:increment).with(hash_including(perform_actions_count: 1))
  end

  it "tracks errors using explicit exception payload" do
    error_event = ActiveSupport::Notifications::Event.new(
      "broadcast.action_cable",
      Time.current,
      Time.current + 0.01,
      "id",
      {exception: ["RuntimeError", "boom"]}
    )

    described_class.call(event: error_event, buffer: buffer)

    expect(buffer).to have_received(:increment).with(hash_including(broadcasts_count: 1, errors_count: 1))
  end
end
