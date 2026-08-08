# frozen_string_literal: true

require_relative "base"

module SolidObserver
  module Channels
    class Email < Base
      def deliver(alert_history, payload)
        AlertMailer.notification_email(alert_history, payload, SolidObserver.config.email_recipients).deliver_now
      end
    end
  end
end
