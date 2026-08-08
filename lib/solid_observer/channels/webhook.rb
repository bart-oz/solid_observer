# frozen_string_literal: true

require "json"
require "openssl"
require_relative "base"

module SolidObserver
  module Channels
    class Webhook < Base
      def deliver(_alert_history, payload)
        body = payload.to_json
        post_json(SolidObserver.config.webhook_endpoint_url, body, headers: signature_headers(body))
      end

      private

      def signature_headers(body)
        secret = SolidObserver.config.webhook_secret
        return {} if secret.blank?

        {"X-Solid-Observer-Signature" => OpenSSL::HMAC.hexdigest("SHA256", secret, body)}
      end
    end
  end
end
