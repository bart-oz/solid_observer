# frozen_string_literal: true

require "digest"

module SolidObserver
  module Services
    class RecordCacheEvent
      def self.call(event:, buffer:)
        new(event, buffer).call
      end

      def initialize(event, buffer)
        @event = event
        @buffer = buffer
      end

      def call
        record_metric_and_event
      rescue => error
        raise error if error.is_a?(NameError)
        Rails.logger&.warn("[SolidObserver] Cache event recording failed: #{error.message}") if defined?(Rails)
      end

      private

      def record_metric_and_event
        SolidObserver::Services::RecordCacheMetric.call(event: @event)
        return unless should_store_event?

        @buffer.push(build_event_data)
      end

      def should_store_event?
        sampled? || slow? || errored?
      end

      def sampled?
        rand <= SolidObserver.config.cache_sampling_rate
      end

      def slow?
        duration_in_seconds && duration_in_seconds >= SolidObserver.config.cache_slow_threshold
      end

      def errored?
        return false unless SolidObserver.config.cache_store_errors

        !exception_data.compact.empty?
      end

      def build_event_data
        {
          event_type: cache_operation,
          key_digest: key_digest,
          hit: hit_value,
          duration: duration_in_seconds,
          error_class: exception_data[:error_class],
          error_message: exception_data[:error_message],
          metadata: metadata.to_json,
          recorded_at: Time.current
        }
      end

      def cache_operation
        @event.name.delete_suffix(".active_support")
      end

      def duration_in_seconds
        @event.duration&./(1000.0)
      end

      def key_digest
        Digest::SHA256.hexdigest(normalized_key_string)
      end

      def normalized_key_string
        key = payload[:key]

        case key
        when Hash
          key.keys.map(&:to_s).sort.join(",")
        when Array
          key.map(&:to_s).sort.join(",")
        else
          key.to_s
        end
      end

      def hit_value
        hit = payload[:hit]
        hits = payload[:hits]

        return hit unless hit.nil?
        return nil unless hits.is_a?(Array)

        hits.any?
      end

      def metadata
        {
          super_operation: payload[:super_operation]&.to_s,
          key_size: key_size,
          hits_count: hits_count
        }.compact.merge(exception_data).compact
      end

      def key_size
        key = payload[:key]
        return key.keys.size if key.is_a?(Hash)
        return key.size if key.is_a?(Array)

        key.to_s.bytesize
      end

      def hits_count
        hits = payload[:hits]
        return nil unless hits.is_a?(Array)

        hits.size
      end

      def exception_data
        @exception_data ||= begin
          exception_obj = payload[:exception_object]
          exception = payload[:exception]

          if exception_obj
            {error_class: exception_obj.class.name, error_message: exception_obj.message}
          elsif exception.is_a?(Array)
            {error_class: exception.first, error_message: exception.last}
          else
            {}
          end
        end
      end

      def payload
        @event.payload || {}
      end
    end
  end
end
