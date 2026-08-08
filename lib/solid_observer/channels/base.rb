# frozen_string_literal: true

require "net/http"
require "uri"

module SolidObserver
  module Channels
    class Base
      OPEN_TIMEOUT = 5
      READ_TIMEOUT = 5

      def deliver(_alert_history, _payload)
        raise NotImplementedError, "#{self.class} must implement #deliver"
      end

      protected

      def post_json(url, body, headers: {})
        uri = URI.parse(url)
        response = http_client(uri).request(build_request(uri, body, headers))
        response.value
        response
      end

      private

      def http_client(uri)
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == "https"
        http.open_timeout = OPEN_TIMEOUT
        http.read_timeout = READ_TIMEOUT
        http
      end

      def build_request(uri, body, headers)
        request = Net::HTTP::Post.new(uri, {"Content-Type" => "application/json"}.merge(headers))
        request.body = body
        request
      end
    end
  end
end
