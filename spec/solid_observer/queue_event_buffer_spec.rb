# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueEventBuffer do
  subject(:buffer) { described_class.instance }

  after do
    buffer.clear
  end

  describe "#push" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    it "adds event to buffer" do
      buffer.push(event_data)
      expect(buffer.size).to eq(1)
    end

    context "when buffer reaches configured size" do
      before do
        allow(SolidObserver.config).to receive(:buffer_size).and_return(3)
        allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
      end

      it "triggers flush automatically" do
        3.times { buffer.push(event_data) }

        expect(SolidObserver::Services::FlushEventBuffer).to have_received(:call)
        expect(buffer.size).to eq(0)
      end
    end
  end

  describe "#flush!" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
    end

    context "with events in buffer" do
      before do
        3.times { buffer.push(event_data) }
        allow(SolidObserver.config).to receive(:buffer_size).and_return(1000)
      end

      it "calls FlushEventBuffer service" do
        buffer.flush!

        expect(SolidObserver::Services::FlushEventBuffer).to have_received(:call).with(
          array_including(event_data)
        )
      end

      it "clears the buffer" do
        buffer.flush!

        expect(buffer.size).to eq(0)
      end
    end

    context "with empty buffer" do
      it "does not call FlushEventBuffer service" do
        buffer.flush!

        expect(SolidObserver::Services::FlushEventBuffer).not_to have_received(:call)
      end
    end

    context "when flush fails" do
      before do
        buffer.push(event_data)
        allow(SolidObserver.config).to receive(:buffer_size).and_return(1000)
        allow(SolidObserver::Services::FlushEventBuffer).to receive(:call).and_raise(StandardError, "Flush failed")
        allow(Rails).to receive(:logger).and_return(double(error: nil))
      end

      it "returns events to buffer" do
        buffer.flush!

        expect(buffer.size).to eq(1)
      end

      it "logs the error" do
        buffer.flush!

        expect(Rails.logger).to have_received(:error).with(
          "[SolidObserver] Buffer flush failed: Flush failed"
        )
      end
    end
  end

  describe "#size" do
    it "returns 0 for empty buffer" do
      expect(buffer.size).to eq(0)
    end

    it "returns correct count for non-empty buffer" do
      3.times { buffer.push({event_type: "test"}) }
      allow(SolidObserver.config).to receive(:buffer_size).and_return(1000)

      expect(buffer.size).to eq(3)
    end
  end

  describe "#clear" do
    it "empties the buffer" do
      3.times { buffer.push({event_type: "test"}) }
      allow(SolidObserver.config).to receive(:buffer_size).and_return(1000)

      buffer.clear

      expect(buffer.size).to eq(0)
    end
  end

  describe "thread safety" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver.config).to receive(:buffer_size).and_return(1000)
      allow(SolidObserver.config).to receive(:flush_interval).and_return(10)
    end

    it "handles concurrent pushes safely" do
      threads = 10.times.map do
        Thread.new do
          10.times { buffer.push(event_data) }
        end
      end

      threads.each(&:join)

      expect(buffer.size).to eq(100)
    end

    it "handles concurrent push and flush safely" do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)

      push_thread = Thread.new do
        20.times { buffer.push(event_data) }
      end

      flush_thread = Thread.new do
        sleep(0.01)
        buffer.flush!
      end

      push_thread.join
      flush_thread.join

      expect(buffer.size).to be >= 0
      expect(buffer.size).to be <= 20
    end
  end

  describe "singleton pattern" do
    it "returns same instance" do
      instance1 = described_class.instance
      instance2 = described_class.instance

      expect(instance1).to be(instance2)
    end

    it "cannot be instantiated directly" do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end
end
