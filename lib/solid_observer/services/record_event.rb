# frozen_string_literal: true

module SolidObserver
  module Services
    class RecordEvent
      def self.call(event:, event_type:, buffer:, metric_name:)
        new(event, event_type, buffer, metric_name).call
      end

      def initialize(event, event_type, buffer, metric_name)
        @event = event
        @event_type = event_type
        @buffer = buffer
        @metric_name = metric_name
      end

      def call
        return unless should_record?

        @buffer.push(build_event_data)
        increment_metric
      rescue => e
        handle_error(e)
      end

      private

      def should_record?
        rand <= SolidObserver.config.sampling_rate
      end

      def build_event_data
        {
          event_type: @event_type,
          correlation_id: CorrelationIdResolver.resolve(@event),
          duration: @event.duration,
          metadata: extract_metadata.to_json,
          recorded_at: Time.current
        }
      end

      def extract_metadata
        payload = @event.payload || {}
        exception_obj = payload[:exception_object]

        {
          job_id: payload.dig(:job, :job_id),
          job_class: payload.dig(:job, :class_name) || payload.dig(:job, :job_class),
          queue_name: payload.dig(:job, :queue_name),
          arguments: payload.dig(:job, :arguments),
          executions: payload.dig(:job, :executions),
          exception_class: exception_obj&.class&.name || payload[:exception]&.first,
          exception_message: exception_obj&.message || payload[:exception]&.last,
          enqueued_at: payload.dig(:job, :enqueued_at),
          priority: payload.dig(:job, :priority)
        }.compact
      rescue => e
        Rails.logger.warn "[SolidObserver] Failed to extract metadata: #{e.message}" if defined?(Rails)
        {}
      end

      def increment_metric
        period = Time.current.beginning_of_hour
        QueueMetric.increment(metric: @metric_name, period: period)
      rescue => e
        Rails.logger.warn "[SolidObserver] Metric increment failed: #{e.message}" if defined?(Rails)
      end

      def handle_error(exception)
        return unless defined?(Rails) && Rails.logger
        Rails.logger.warn "[SolidObserver] Event recording failed: #{exception.message}"
      end
    end
  end
end
