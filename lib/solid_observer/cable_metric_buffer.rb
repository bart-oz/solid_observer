# frozen_string_literal: true

require "singleton"
require "concurrent/timer_task"

require_relative "services/flush_cable_metrics"

module SolidObserver
  class CableMetricBuffer
    include Singleton

    INITIAL_METRICS = {
      flush_failures_count: 0,
      drops_count: 0,
      last_flush_at: nil,
      last_flush_duration_ms: nil,
      last_flush_error: nil
    }.freeze

    def initialize
      @store = MetricStore.new
      @timer_mutex = Mutex.new
      @timer_task = nil
    end

    def increment(metric_data)
      config = SolidObserver.config
      return unless config.persistence_mode?

      @store.add(metric_data)
      ensure_timer_running
      flush! if size >= config.buffer_size
    end

    def flush!
      metrics_to_flush = @store.drain
      return if metrics_to_flush.empty?

      flush_metrics(metrics_to_flush, monotonic_ms)
    end

    def flush
      flush!
    end

    def size
      @store.size
    end

    def clear
      @store.clear
    end

    def metrics
      @store.metrics
    end

    def shutdown
      stop_timer
      flush!
    end

    private

    def ensure_timer_running
      timer_to_start, timer_to_stop = replace_timer_if_stopped
      return unless timer_to_start

      timer_to_stop&.shutdown
      timer_to_start.execute
    end

    def replace_timer_if_stopped
      @timer_mutex.synchronize do
        current_timer_task = @timer_task
        return [nil, nil] if current_timer_task && !current_timer_task.shuttingdown?

        [build_timer_task, current_timer_task]
      end
    end

    def stop_timer
      timer_to_stop = @timer_mutex.synchronize do
        current_timer = @timer_task
        @timer_task = nil
        current_timer
      end

      timer_to_stop&.shutdown
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

    def flush_metrics(metrics_to_flush, started_at_ms)
      Services::FlushCableMetrics.call(metrics_to_flush)
      @store.record_flush_success(monotonic_ms - started_at_ms)
    rescue => error
      handle_flush_error(error, metrics_to_flush)
    end

    def handle_flush_error(error, metrics_to_flush)
      @store.requeue(metrics_to_flush)
      @store.record_flush_failure(error)
      Rails.logger&.error("[SolidObserver] Cable metric buffer flush failed: #{error.message}") if defined?(Rails)
    end

    class MetricStore
      COUNTERS = %i[
        broadcasts_count
        transmissions_count
        confirmations_count
        rejections_count
        perform_actions_count
        errors_count
      ].freeze

      def initialize
        @mutex = Mutex.new
        @buffer = {}
        @metrics = INITIAL_METRICS.dup
      end

      def add(metric_data)
        @mutex.synchronize { add_metric(metric_data) }
      end

      def drain
        @mutex.synchronize do
          drained = @buffer.values.map(&:dup)
          @buffer.clear
          drained
        end
      end

      def requeue(metrics_to_flush)
        @mutex.synchronize { add_metrics_with_capacity(metrics_to_flush + @buffer.values) }
      end

      def clear
        @mutex.synchronize { @buffer.clear }
      end

      def size
        @mutex.synchronize { @buffer.size }
      end

      def metrics
        @mutex.synchronize do
          {
            size: @buffer.size,
            max_buffer_size: SolidObserver.config.max_buffer_size
          }.merge(@metrics.dup)
        end
      end

      def record_flush_success(duration_ms)
        @mutex.synchronize do
          @metrics.merge!(
            last_flush_at: Time.current,
            last_flush_duration_ms: duration_ms,
            last_flush_error: nil
          )
        end
      end

      def record_flush_failure(error)
        @mutex.synchronize do
          @metrics[:flush_failures_count] += 1
          @metrics[:last_flush_error] = error.message
        end
      end

      private

      def add_metric(metric_data)
        config = SolidObserver.config
        key = metric_data.fetch(:period_start)
        if @buffer.key?(key)
          merge_metric(@buffer.fetch(key), metric_data)
        elsif @buffer.size < config.max_buffer_size
          @buffer[key] = metric_hash(metric_data)
        else
          handle_overflow(key, metric_data)
        end
      end

      def add_metrics_with_capacity(metrics)
        @buffer.clear
        metrics.each { |metric| add_metric(metric) }
      end

      def handle_overflow(key, metric_data)
        drop_count = if SolidObserver.config.buffer_overflow_strategy == :drop_old
          replace_old_metric(key, metric_data)
        else
          COUNTERS.sum { |counter| metric_data.fetch(counter, 0).to_i }
        end

        @metrics[:drops_count] += drop_count
      end

      def replace_old_metric(key, metric_data)
        dropped = @buffer.shift&.last
        @buffer[key] = metric_hash(metric_data)
        dropped ? COUNTERS.sum { |counter| dropped.fetch(counter, 0).to_i } : 0
      end

      def merge_metric(target, metric_data)
        COUNTERS.each do |counter|
          target[counter] += metric_data.fetch(counter, 0).to_i
        end
      end

      def metric_hash(metric_data)
        COUNTERS.each_with_object({period_start: metric_data.fetch(:period_start)}) do |counter, hash|
          hash[counter] = metric_data.fetch(counter, 0).to_i
        end
      end
    end
  end
end
