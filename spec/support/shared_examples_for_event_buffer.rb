# frozen_string_literal: true

RSpec.shared_examples "an event buffer" do |flush_service:, log_label:, event_factory:|
  subject(:buffer) { described_class.instance }

  let(:event_data) { event_factory.call }

  before do
    SolidObserver.reset_configuration!
    buffer.clear
    buffer.shutdown
    allow(flush_service).to receive(:call)
  end

  after do
    buffer.clear
    buffer.shutdown
    SolidObserver.reset_configuration!
  end

  after(:all) do
    described_class.instance.clear
    described_class.instance.shutdown
  end

  describe "#push" do
    it "adds an event to the buffer" do
      buffer.push(event_data)

      expect(buffer.size).to eq(1)
    end

    it "triggers flush when the configured threshold is reached" do
      SolidObserver.config.buffer_size = 3

      3.times { buffer.push(event_data) }

      expect(flush_service).to have_received(:call)
      expect(buffer.size).to eq(0)
    end

    it "does not buffer in realtime mode" do
      SolidObserver.config.storage_mode = :realtime

      buffer.push(event_data)

      expect(buffer.size).to eq(0)
    end
  end

  describe "#flush!" do
    it "calls the configured flush service with buffered events" do
      SolidObserver.config.buffer_size = 1000
      3.times { buffer.push(event_data) }

      buffer.flush!

      expect(flush_service).to have_received(:call).with(array_including(event_data))
    end

    it "clears the buffer after successful flush" do
      buffer.push(event_data)

      buffer.flush!

      expect(buffer.size).to eq(0)
    end

    it "does not call the flush service for an empty buffer" do
      buffer.flush!

      expect(flush_service).not_to have_received(:call)
    end

    it "requeues events and logs when flush fails" do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(flush_service).to receive(:call).and_raise(StandardError, "DB down")
      buffer.push(event_data)

      buffer.flush!

      expect(buffer.size).to eq(1)
      expect(logger).to have_received(:error).with("[SolidObserver] #{log_label} flush failed: DB down")
    end
  end

  describe "#flush" do
    it "is a safe alias for #flush!" do
      buffer.push(event_data)

      buffer.flush

      expect(flush_service).to have_received(:call).with([event_data])
      expect(buffer.size).to eq(0)
    end
  end

  describe "#size" do
    it "returns 0 for an empty buffer" do
      expect(buffer.size).to eq(0)
    end

    it "returns the count for a non-empty buffer" do
      3.times { buffer.push(event_data) }

      expect(buffer.size).to eq(3)
    end
  end

  describe "#clear" do
    it "empties the buffer without flushing" do
      buffer.push(event_data)

      buffer.clear

      expect(buffer.size).to eq(0)
      expect(flush_service).not_to have_received(:call)
    end
  end

  describe "thread safety" do
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 10
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
      push_thread = Thread.new { 20.times { buffer.push(event_data) } }
      flush_thread = Thread.new { buffer.flush! }

      push_thread.join
      flush_thread.join

      expect(buffer.size).to be_between(0, 20).inclusive
    end
  end

  describe "singleton pattern" do
    it "returns the same instance" do
      first_instance = described_class.instance
      second_instance = described_class.instance

      expect(first_instance).to be(second_instance)
    end

    it "cannot be instantiated directly" do
      expect { described_class.new }.to raise_error(NoMethodError)
    end
  end

  describe "#metrics" do
    it "returns QueueEventBuffer-compatible metric keys" do
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
      allow(flush_service).to receive(:call).and_raise(StandardError, "DB down")

      initial_failures = buffer.metrics[:flush_failures_count]
      buffer.push(event_data)
      buffer.flush!

      metrics = buffer.metrics
      expect(metrics[:flush_failures_count]).to eq(initial_failures + 1)
      expect(metrics[:last_flush_error]).to eq("DB down")
    end
  end

  describe "#shutdown" do
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.flush_interval = 60
    end

    it "drains buffered events and stops the timer" do
      2.times { buffer.push(event_data) }
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil

      buffer.shutdown

      expect(flush_service).to have_received(:call).with(array_including(event_data))
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
      SolidObserver.config.buffer_size = 3
      SolidObserver.config.max_buffer_size = 3
      allow(SolidObserver.config).to receive(:buffer_size).and_return(100)
    end

    context "when strategy is :drop_old" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_old
      end

      it "keeps newest events and tracks drops" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push(event_data.merge(id: i + 1)) }

        flushed_events = nil
        allow(flush_service).to receive(:call) { |events| flushed_events = events }
        buffer.flush!

        expect(flushed_events.map { |event| event[:id] }).to eq([3, 4, 5])
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end

    context "when strategy is :drop_new" do
      before do
        SolidObserver.config.buffer_overflow_strategy = :drop_new
      end

      it "keeps oldest events and tracks drops" do
        initial_drops = buffer.metrics[:drops_count]
        5.times { |i| buffer.push(event_data.merge(id: i + 1)) }

        flushed_events = nil
        allow(flush_service).to receive(:call) { |events| flushed_events = events }
        buffer.flush!

        expect(flushed_events.map { |event| event[:id] }).to eq([1, 2, 3])
        expect(buffer.metrics[:drops_count]).to eq(initial_drops + 2)
      end
    end
  end

  describe "failure resilience" do
    before do
      logger = instance_double(Logger, error: nil)
      allow(Rails).to receive(:logger).and_return(logger)
      allow(flush_service).to receive(:call).and_raise(StandardError, "DB down")
      SolidObserver.config.buffer_size = 25
      SolidObserver.config.max_buffer_size = 50
      SolidObserver.config.flush_interval = 60
      SolidObserver.config.buffer_overflow_strategy = :drop_old
    end

    it "keeps the buffer bounded during consecutive failing flushes" do
      10.times do
        100.times { buffer.push(event_data) }
        buffer.flush!

        expect(buffer.size).to be <= 50
      end
    end
  end

  describe "high-concurrency pushes" do
    before do
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
    before do
      SolidObserver.config.buffer_size = 1000
      SolidObserver.config.max_buffer_size = 10_000
      SolidObserver.config.flush_interval = 0.02
    end

    it "starts lazily on first push" do
      expect(buffer.instance_variable_get(:@timer_task)).to be_nil

      buffer.push(event_data)
      expect(buffer.instance_variable_get(:@timer_task)).not_to be_nil
    end

    it "flushes when the timer callback runs" do
      trigger_timer = stub_timer_callback

      buffer.push(event_data)
      trigger_timer.call

      expect(flush_service).to have_received(:call).with([event_data])
      expect(buffer.size).to eq(0)
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

  def stub_timer_callback
    timer_callback = nil
    timer_task = instance_double(Concurrent::TimerTask, execute: nil, shutdown: nil, shuttingdown?: false)

    allow(Concurrent::TimerTask).to receive(:new) do |**_options, &block|
      timer_callback = block
      timer_task
    end

    -> { timer_callback.call }
  end
end
