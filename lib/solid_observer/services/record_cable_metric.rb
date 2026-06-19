# frozen_string_literal: true

require_relative "../cable_metric_buffer"

module SolidObserver
  module Services
    class RecordCableMetric
      COUNTERS = %i[
        broadcasts_count
        transmissions_count
        confirmations_count
        rejections_count
        perform_actions_count
        errors_count
      ].freeze

      EVENT_COUNTER_MAP = {
        "broadcast.action_cable" => :broadcasts_count,
        "transmit.action_cable" => :transmissions_count,
        "transmit_subscription_confirmation.action_cable" => :confirmations_count,
        "transmit_subscription_rejection.action_cable" => :rejections_count,
        "perform_action.action_cable" => :perform_actions_count
      }.freeze

      def self.call(event:, buffer: SolidObserver::CableMetricBuffer.instance)
        new(event, buffer).call
      end

      def initialize(event, buffer)
        @event = event
        @buffer = buffer
      end

      def call
        @buffer.increment(metric_data)
      rescue => error
        Rails.logger&.warn("[SolidObserver] Cable metric recording failed: #{error.message}") if defined?(Rails)
      end

      private

      def metric_data
        COUNTERS.each_with_object({period_start: period_start}) do |counter, data|
          data[counter] = (counter == target_counter) ? 1 : 0
        end.merge(errors_count: error_increment)
      end

      def target_counter
        EVENT_COUNTER_MAP.fetch(event_name, :broadcasts_count)
      end

      def period_start
        Time.current.beginning_of_minute
      end

      def event_name
        @event.name
      end

      def error_increment
        exception_present? ? 1 : 0
      end

      def exception_present?
        payload[:exception_object].present? || payload[:exception].is_a?(Array)
      end

      def payload
        @event.payload || {}
      end
    end
  end
end
