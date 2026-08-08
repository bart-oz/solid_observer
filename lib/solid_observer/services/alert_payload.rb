# frozen_string_literal: true

module SolidObserver
  module Services
    class AlertPayload
      RELATIVE_PATH = "/solid_observer"

      def self.call(alert_history:, event_type: nil)
        new(alert_history: alert_history, event_type: event_type).call
      end

      def initialize(alert_history:, event_type: nil)
        @alert_history = alert_history
        @event_type = event_type
      end

      def call
        data = alert_history.payload
        {
          rule_name: data["rule_name"],
          severity: data["severity"],
          metric_type: data["metric_type"],
          metric_value: alert_history.metric_value,
          triggered_at: alert_history.triggered_at,
          environment: data["environment"],
          deep_link_url: deep_link_url,
          event_type: (event_type || alert_history.state).to_s
        }
      end

      private

      attr_reader :alert_history, :event_type

      def deep_link_url
        base_url = SolidObserver.config.notification_base_url
        return relative_deep_link_url if base_url.blank?

        "#{base_url}#{RELATIVE_PATH}"
      end

      def relative_deep_link_url
        Rails.logger&.warn("[SolidObserver] notification_base_url is not configured; using relative deep link") if defined?(Rails)
        RELATIVE_PATH
      end
    end
  end
end
