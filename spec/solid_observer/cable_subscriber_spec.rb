# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CableSubscriber do
  before do
    described_class.unsubscribe!
    allow(SolidObserver::Services::RecordCableEvent).to receive(:call)
  end

  after { described_class.unsubscribe! }

  it "subscribes only when solid cable is enabled" do
    allow(SolidObserver.config).to receive(:solid_cable_enabled?).and_return(false)

    described_class.subscribe!

    expect(described_class.subscribed?).to be(false)
  end

  it "subscribes to configured cable events" do
    allow(SolidObserver.config).to receive(:solid_cable_enabled?).and_return(true)

    described_class.subscribe!
    ActiveSupport::Notifications.instrument("broadcast.action_cable", {broadcasting: "chat:1"})

    expect(SolidObserver::Services::RecordCableEvent).to have_received(:call).with(
      hash_including(buffer: SolidObserver::CableEventBuffer.instance, event: be_a(ActiveSupport::Notifications::Event))
    )
  end

  it "unsubscribes from all notifications" do
    allow(SolidObserver.config).to receive(:solid_cable_enabled?).and_return(true)

    described_class.subscribe!
    described_class.unsubscribe!

    expect(described_class.subscribed?).to be(false)
  end
end
