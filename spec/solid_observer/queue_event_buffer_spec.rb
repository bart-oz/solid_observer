# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::QueueEventBuffer do
  subject(:buffer) { described_class.instance }

  before do
    SolidObserver.reset_configuration!
    buffer.shutdown
    buffer.clear
  end

  after do
    buffer.clear
    buffer.shutdown
    SolidObserver.reset_configuration!
  end

  after(:all) do
    described_class.instance.shutdown
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

    context "when in realtime mode" do
      before do
        allow(SolidObserver.config).to receive(:persistence_mode?).and_return(false)
      end

      it "does not add event to buffer" do
        buffer.push(event_data)
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

      push_thread = Thread.new { 20.times { buffer.push(event_data) } }
      flush_thread = Thread.new { buffer.flush! }

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

  describe "#metrics" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
    end

    it "returns exactly the expected keys" do
      expect(buffer.metrics.keys).to eq(
        %i[
          size
          max_buffer_size
          flush_failures_count
          drops_count
          last_flush_at
          last_flush_duration_ms
          last_flush_error
        ]
      )
    end

    it "tracks successful flush metadata" do
      buffer.push(event_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:last_flush_at]).to be_a(Time)
      expect(metrics[:last_flush_duration_ms]).to be_a(Numeric)
      expect(metrics[:last_flush_error]).to be_nil
    end

    it "tracks flush failures and last error" do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call).and_raise(StandardError, "DB down")

      initial_failures = buffer.metrics[:flush_failures_count]
      buffer.push(event_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:flush_failures_count]).to eq(initial_failures + 1)
      expect(metrics[:last_flush_error]).to eq("DB down")
    end
  end

  describe "#shutdown" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 60
    end

    it "drains buffered events and stops the timer" do
      2.times { buffer.push(event_data) }
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil

      buffer.shutdown

      expect(SolidObserver::Services::FlushEventBuffer).to have_received(:call).with(array_including(event_data))
      expect(buffer.size).to eq(0)
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil
    end

    it "allows timer restart after shutdown on subsequent push" do
      buffer.push(event_data)
      buffer.shutdown

      expect(buffer.instance_variable_get(:@timer_task)).to be_nil

      buffer.push(event_data)

      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil
    end
  end

  describe "overflow policy" do
    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
      SolidObserver.config.buffer_size = 3
      SolidObserver.config.max_buffer_size = 3
      allow(SolidObserver.config).to receive(:buffer_size).and_return(100)
    end

    context "when strategy is :drop_old" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_old
      end

      it "keeps newest events when over capacity" do
        5.times { |i| buffer.push({id: i + 1, event_type: "test"}) }

        payload = nil
        allow(SolidObserver::Services::FlushEventBuffer).to receive(:call) { |events| payload = events }
        buffer.flush!

        expect(payload.map { |event| event[:id] }).to eq([3, 4, 5])
      end

      it "increments drops_count when overflowing" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push({id: i + 1, event_type: "test"}) }

        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end

    context "when strategy is :drop_new" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_new
      end

      it "keeps oldest events when over capacity" do
        5.times { |i| buffer.push({id: i + 1, event_type: "test"}) }

        payload = nil
        allow(SolidObserver::Services::FlushEventBuffer).to receive(:call) { |events| payload = events }
        buffer.flush!

        expect(payload.map { |event| event[:id] }).to eq([1, 2, 3])
      end

      it "increments drops_count when overflowing" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push({id: i + 1, event_type: "test"}) }

        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end
  end

  describe "failure resilience" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call).and_raise(StandardError, "DB down")
      SolidObserver.config.buffer_size = 25
      SolidObserver.config.max_buffer_size = 50
      SolidObserver.config.flush_interval = 60
      SolidObserver.config.buffer_overflow_strategy = :drop_old
    end

    it "keeps buffer bounded during 100 consecutive failing flushes" do
      100.times do
        100.times { buffer.push(event_data) }
        buffer.flush!
        expect(buffer.size).to be <= 50
      end
    end
  end

  describe "high-concurrency pushes" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
      SolidObserver.config.max_buffer_size = 5000
      SolidObserver.config.buffer_size = 5000
      allow(SolidObserver.config).to receive(:buffer_size).and_return(20_000)
      SolidObserver.config.flush_interval = 60
      SolidObserver.config.buffer_overflow_strategy = :drop_old
    end

    it "preserves invariant: size + drops_count == pushes" do
      initial_drops = buffer.metrics[:drops_count]
      threads = 100.times.map do
        Thread.new do
          100.times { buffer.push(event_data) }
        end
      end
      threads.each(&:join)

      metrics = buffer.metrics
      expect(metrics[:size] + (metrics[:drops_count] - initial_drops)).to eq(10_000)
      expect(metrics[:size]).to be <= 5000
    end
  end

  describe "timer lifecycle" do
    let(:event_data) { {event_type: "test", recorded_at: Time.current} }

    before do
      allow(SolidObserver::Services::FlushEventBuffer).to receive(:call)
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.max_buffer_size = 10_000
      SolidObserver.config.flush_interval = 0.02
    end

    it "starts lazily on first push" do
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil

      buffer.push(event_data)

      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil
    end

    it "uses one persistent timer across flush cycles without thread growth" do
      baseline_threads = Thread.list.size

      buffer.push(event_data)
      timer_task = buffer.instance_variable_get(:@timer_task)

      10.times do
        buffer.flush!
        buffer.push(event_data)
        expect(buffer.instance_variable_get(:@timer_task)).to be(timer_task)
      end

      expect(Thread.list.size).to be <= baseline_threads + 4
    end
  end
end
