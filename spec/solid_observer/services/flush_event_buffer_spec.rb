# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Services::FlushEventBuffer do
  let(:events) do
    [
      {event_type: "job_completed", correlation_id: "123", recorded_at: Time.current, metadata: "{}"},
      {event_type: "job_failed", correlation_id: "456", recorded_at: Time.current, metadata: "{}"}
    ]
  end

  describe ".call" do
    it "creates an instance and calls #call" do
      service_instance = instance_double(described_class)
      allow(described_class).to receive(:new).and_return(service_instance)
      allow(service_instance).to receive(:call)

      described_class.call(events)

      expect(described_class).to have_received(:new).with(events)
      expect(service_instance).to have_received(:call)
    end
  end

  describe "#call" do
    subject(:service) { described_class.new(events) }

    context "with valid events" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
        allow(SolidObserver::QueueEvent).to receive(:insert_all!)
      end

      it "wraps insert in transaction" do
        service.call

        expect(SolidObserver::QueueEvent).to have_received(:transaction)
      end

      it "uses insert_all! for batch insert" do
        service.call

        expect(SolidObserver::QueueEvent).to have_received(:insert_all!).with(events)
      end
    end

    context "with empty events array" do
      let(:events) { [] }

      before do
        allow(SolidObserver::QueueEvent).to receive(:insert_all!)
      end

      it "does not attempt insert" do
        service.call

        expect(SolidObserver::QueueEvent).not_to have_received(:insert_all!)
      end
    end

    context "when insert_all! raises RecordInvalid" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
        allow(SolidObserver::QueueEvent).to receive(:insert_all!).and_raise(ActiveRecord::RecordInvalid)
        allow(SolidObserver::QueueEvent).to receive(:insert_all).and_return(true)
        allow(Rails).to receive(:logger).and_return(double(warn: nil))
      end

      it "retries with smaller batches" do
        service.call

        expect(SolidObserver::QueueEvent).to have_received(:insert_all).at_least(:once)
      end

      it "processes events in batches of 100" do
        large_events = 250.times.map { |i| {event_type: "test_#{i}", recorded_at: Time.current} }
        service = described_class.new(large_events)

        service.call

        expect(SolidObserver::QueueEvent).to have_received(:insert_all).exactly(3).times
      end
    end

    context "when batch insert fails partially" do
      let(:events) do
        150.times.map { |i| {event_type: "test_#{i}", recorded_at: Time.current} }
      end

      before do
        allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
        allow(SolidObserver::QueueEvent).to receive(:insert_all!).and_raise(ActiveRecord::RecordInvalid)
        allow(Rails).to receive(:logger).and_return(double(warn: nil))

        call_count = 0
        allow(SolidObserver::QueueEvent).to receive(:insert_all) do
          call_count += 1
          raise StandardError, "DB error" if call_count == 2
          true
        end
      end

      it "logs failed batches but continues" do
        service.call

        expect(Rails.logger).to have_received(:warn).with(
          "[SolidObserver] Failed to insert batch: DB error"
        )
      end

      it "does not raise error" do
        expect { service.call }.not_to raise_error
      end
    end

    context "when transaction fails" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:transaction).and_raise(StandardError, "Transaction error")
        allow(Rails).to receive(:logger).and_return(double(error: nil))
      end

      it "logs the error" do
        expect { service.call }.to raise_error(StandardError, "Transaction error")

        expect(Rails.logger).to have_received(:error).with(
          "[SolidObserver] Event buffer flush failed: Transaction error"
        )
      end

      it "re-raises the error" do
        expect { service.call }.to raise_error(StandardError, "Transaction error")
      end
    end
  end

  describe "transaction rollback behavior" do
    subject(:service) { described_class.new(events) }

    before do
      allow(SolidObserver::QueueEvent).to receive(:transaction).and_yield
      allow(Rails).to receive(:logger).and_return(double(error: nil, warn: nil))
    end

    context "when insert_all! raises RecordInvalid" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:insert_all!).and_raise(ActiveRecord::RecordInvalid)
        allow(SolidObserver::QueueEvent).to receive(:insert_all).and_return(true)
      end

      it "falls back to batch retry without re-raising" do
        expect { service.call }.not_to raise_error
      end

      it "uses smaller batches" do
        service.call
        expect(SolidObserver::QueueEvent).to have_received(:insert_all).at_least(:once)
      end
    end

    context "when other errors occur" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:insert_all!).and_raise(StandardError, "DB connection lost")
      end

      it "logs and re-raises the error" do
        expect { service.call }.to raise_error(StandardError, "DB connection lost")
        expect(Rails.logger).to have_received(:error).with("[SolidObserver] Event buffer flush failed: DB connection lost")
      end
    end
  end
end
