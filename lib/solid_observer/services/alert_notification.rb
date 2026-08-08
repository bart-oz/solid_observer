# frozen_string_literal: true

require "net/http"
require_relative "alert_payload"
require_relative "../channels/slack"
require_relative "../channels/email"
require_relative "../channels/webhook"

module SolidObserver
  module Services
    class AlertNotification
      DeliveryResult = Struct.new(:channel, :status, :error_class, :error_message, :attempted_at, keyword_init: true) do
        def raise_error
          klass = error_class.constantize
          raise((klass < Net::HTTPExceptions) ? klass.new(error_message, nil) : klass.new(error_message))
        end
      end

      CHANNELS = {
        slack: {class: Channels::Slack, configured: ->(config) { config.slack_webhook_url.present? }},
        email: {class: Channels::Email, configured: ->(config) { config.email_recipients.present? }},
        webhook: {class: Channels::Webhook, configured: ->(config) { config.webhook_endpoint_url.present? }}
      }.freeze

      def self.call(alert_history:, event_type: nil, channels: nil)
        new(alert_history: alert_history, event_type: event_type, channels: channels).call
      end

      def initialize(alert_history:, event_type: nil, channels: nil)
        @alert_history = alert_history
        @event_type = event_type
        @channels = channels
      end

      def call
        payload = AlertPayload.call(alert_history: alert_history, event_type: event_type)
        enabled_channel_names.map { |name| deliver_to(name, payload) }
      end

      private

      attr_reader :alert_history, :event_type, :channels

      def enabled_channel_names
        return Array(channels) if channels

        config = SolidObserver.config
        CHANNELS.select { |_name, spec| spec[:configured].call(config) }.keys
      end

      def deliver_to(name, payload)
        CHANNELS.fetch(name)[:class].new.deliver(alert_history, payload)
        success_result(name)
      rescue => e
        failure_result(name, e)
      end

      def success_result(name)
        DeliveryResult.new(channel: name, status: :success, error_class: nil, error_message: nil, attempted_at: Time.current)
      end

      def failure_result(name, error)
        DeliveryResult.new(channel: name, status: :failed, error_class: error.class.name, error_message: error.message, attempted_at: Time.current)
      end
    end
  end
end
