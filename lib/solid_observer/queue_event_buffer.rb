# frozen_string_literal: true

require "singleton"
require "concurrent/timer_task"

module SolidObserver
  # Thread-safe buffer for collecting queue events before batch insertion.
  #
  # Events are buffered in memory and flushed either when:
  # - Buffer size reaches the configured threshold
  # - Flush interval timer expires
  #
  # @example Push an event to the buffer
  #   QueueEventBuffer.instance.push(event_data)
  class QueueEventBuffer
    include Singleton

    INITIAL_METRICS = {
      flush_failures_count: 0,
      drops_count: 0,
      last_flush_at: nil,
      last_flush_duration_ms: nil,
      last_flush_error: nil
    }.freeze

    def initialize
      @mutex = Mutex.new
      @metrics_mutex = Mutex.new
      @buffer = []
      @metrics = INITIAL_METRICS.dup
      @timer_task = nil
    end

    # Adds an event to the buffer and triggers flush if threshold reached.
    #
    # @param event_data [Hash] Event data to buffer
    # @return [void]
    def push(event_data)
      return unless (config = SolidObserver.config).persistence_mode?

      drops_count, should_flush = sync_push_and_check(event_data, config)
      record_drop(drops_count) if drops_count.positive?
      ensure_timer_running
      flush! if should_flush
    end

    # Flushes all buffered events to the database.
    #
    # @return [void]
    def flush!
      events_to_flush = nil

      @mutex.synchronize do
        return if @buffer.empty?
        events_to_flush = @buffer.dup
        @buffer.clear
      end

      started_at_ms = monotonic_ms
      begin
        Services::FlushEventBuffer.call(events_to_flush)
      rescue => e
        requeue_failed_events(events_to_flush)
        record_flush_failure(e)
        Rails.logger&.error "[SolidObserver] Buffer flush failed: #{e.message}" if defined?(Rails)
        return
      end
      record_flush_success(monotonic_ms - started_at_ms)
    end

    def size
      @mutex.synchronize { @buffer.size }
    end

    def clear
      @mutex.synchronize { @buffer.clear }
    end

    def metrics
      current_size = @mutex.synchronize { @buffer.size }
      snapshot = @metrics_mutex.synchronize { @metrics.dup }
      {
        size: current_size,
        max_buffer_size: SolidObserver.config.max_buffer_size
      }.merge(snapshot)
    end

    def shutdown
      stop_timer
      flush!
    end

    private

    def apply_overflow_policy(event_data, config)
      if @buffer.size < config.max_buffer_size
        @buffer << event_data
        return 0
      end

      handle_overflow(event_data, config.buffer_overflow_strategy)
    end

    def handle_overflow(event_data, overflow_strategy)
      case overflow_strategy
      when :drop_old
        @buffer.shift
        @buffer << event_data
      when :drop_new
        # No-op: drop incoming event, keep oldest buffered events.
      else
        raise ArgumentError, "Unsupported buffer_overflow_strategy: #{overflow_strategy.inspect}"
      end

      1
    end

    def requeue_failed_events(events_to_flush)
      return unless events_to_flush

      dropped_count = sync_requeue_events(events_to_flush, SolidObserver.config.max_buffer_size)
      record_drop(dropped_count) if dropped_count.positive?
    end

    def trim_events_for_capacity(events, max_buffer_size)
      dropped_count = events.size - max_buffer_size
      return [events, 0] if dropped_count <= 0

      [events_to_keep(events, max_buffer_size), dropped_count]
    end

    def ensure_timer_running
      timer_to_start, timer_to_stop = replace_timer_if_stopped
      return unless timer_to_start

      timer_to_stop&.shutdown
      timer_to_start.execute
    end

    def replace_timer_if_stopped
      @mutex.synchronize do
        current_timer_task = @timer_task
        return [nil, nil] if timer_running?(current_timer_task)

        [build_timer_task, current_timer_task]
      end
    end

    def stop_timer
      timer_to_stop = @mutex.synchronize do
        current_timer = @timer_task
        @timer_task = nil
        current_timer
      end

      timer_to_stop&.shutdown
    end

    def record_flush_success(duration_ms)
      @metrics_mutex.synchronize do
        @metrics.merge!(
          last_flush_at: Time.current,
          last_flush_duration_ms: duration_ms,
          last_flush_error: nil
        )
      end
    end

    def record_flush_failure(error)
      @metrics_mutex.synchronize do
        @metrics[:flush_failures_count] += 1
        @metrics[:last_flush_error] = error.message
      end
    end

    def record_drop(count = 1)
      @metrics_mutex.synchronize do
        @metrics[:drops_count] += count
      end
    end

    def sync_push_and_check(event_data, config)
      @mutex.synchronize do
        drops_count = apply_overflow_policy(event_data, config)
        [drops_count, @buffer.size >= config.buffer_size]
      end
    end

    def sync_requeue_events(events_to_flush, max_buffer_size)
      @mutex.synchronize do
        combined_events = events_to_flush + @buffer
        kept_events, dropped_count = trim_events_for_capacity(combined_events, max_buffer_size)
        @buffer.replace(kept_events)
        dropped_count
      end
    end

    def events_to_keep(events, max_buffer_size)
      if SolidObserver.config.buffer_overflow_strategy == :drop_old
        events.last(max_buffer_size)
      else
        events.first(max_buffer_size)
      end
    end

    def timer_running?(timer_task)
      timer_task && !timer_task.shuttingdown?
    end

    def build_timer_task
      @timer_task = Concurrent::TimerTask.new(
        execution_interval: SolidObserver.config.flush_interval,
        run_now: false
      ) { flush! }
    end

    def monotonic_ms
      Process.clock_gettime(Process::CLOCK_MONOTONIC, :millisecond)
    end
  end
end
