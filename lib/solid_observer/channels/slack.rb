# frozen_string_literal: true

require "json"
require_relative "base"

module SolidObserver
  module Channels
    class Slack < Base
      def deliver(_alert_history, payload)
        response = post_json(SolidObserver.config.slack_webhook_url, slack_body(payload))
        raise_on_slack_failure(response)
      end

      private

      def slack_body(payload)
        {text: slack_text(payload)}.to_json
      end

      def slack_text(payload)
        "[#{payload[:event_type]}] #{payload[:rule_name]} (#{payload[:severity]}): " \
          "#{payload[:metric_type]} = #{payload[:metric_value]} in #{payload[:environment]}. #{payload[:deep_link_url]}"
      end

      def raise_on_slack_failure(response)
        body = JSON.parse(response.body)
        return unless slack_failure?(body)

        raise Net::HTTPClientException.new("Slack delivery failed: #{body["error"]}", response)
      rescue JSON::ParserError
        nil
      end

      def slack_failure?(body)
        body.is_a?(Hash) && body["ok"] == false
      end
    end
  end
end
