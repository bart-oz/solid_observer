# frozen_string_literal: true

require "net/http"

module SolidObserver
  class NotificationDeliveryJob < ActiveJob::Base
    queue_as :default

    retry_on Net::OpenTimeout, Net::ReadTimeout, Net::WriteTimeout,
      Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError, Net::HTTPFatalError,
      attempts: 3

    discard_on Net::HTTPClientException do |_job, error|
      Rails.logger.warn("[SolidObserver] NotificationDeliveryJob discarded: #{error.class}: #{error.message}")
    end

    def perform(alert_history_id, event_type = nil)
      alert_history = SolidObserver::AlertHistory.find(alert_history_id)
      results = Services::AlertNotification.call(alert_history: alert_history, event_type: event_type)
      reraise_first_failure(results)
    end

    private

    def reraise_first_failure(results)
      results.find { |result| result.status == :failed }&.raise_error
    end
  end
end
