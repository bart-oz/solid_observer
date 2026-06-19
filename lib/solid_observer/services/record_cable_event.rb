# frozen_string_literal: true

require "digest"

module SolidObserver
  module Services
    class RecordCableEvent
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
        Rails.logger&.warn("[SolidObserver] Cable event recording failed: #{error.message}") if defined?(Rails)
      end

      private

      def record_metric_and_event
        SolidObserver::Services::RecordCableMetric.call(event: @event)
        return unless should_store_event?

        @buffer.push(build_event_data)
      end

      def should_store_event?
        case @event.name
        when "broadcast.action_cable"
          sampled? || errored?
        when "transmit_subscription_rejection.action_cable"
          true
        else
          false
        end
      end

      def sampled?
        rand <= SolidObserver.config.cable_sampling_rate
      end

      def errored?
        !exception_data.compact.empty?
      end

      def build_event_data
        {
          event_type: @event.name.delete_suffix(".action_cable"),
          channel_class: channel_class,
          broadcasting_digest: broadcasting_digest,
          duration: duration_in_seconds,
          error_class: exception_data[:error_class],
          error_message: exception_data[:error_message],
          metadata: metadata.to_json,
          recorded_at: Time.current
        }
      end

      def broadcasting_digest
        return nil unless @event.name == "broadcast.action_cable"

        Digest::SHA256.hexdigest(payload[:broadcasting].to_s)
      end

      def channel_class
        class_name = payload[:channel_class]
        return class_name if class_name

        channel = payload[:channel]
        return nil unless channel

        channel.class.name || channel.to_s
      end

      def duration_in_seconds
        @event.duration&./(1000.0)
      end

      def metadata
        {
          action: payload[:action]&.to_s,
          via: payload[:via]&.to_s,
          data_size: payload[:data]&.to_s&.bytesize,
          message_size: payload[:message]&.to_s&.bytesize
        }.compact
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
