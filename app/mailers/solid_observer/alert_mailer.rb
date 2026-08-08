# frozen_string_literal: true

module SolidObserver
  class AlertMailer < ActionMailer::Base
    default from: "notifications@solid-observer.local"

    def notification_email(alert_history, payload, recipients)
      @alert_history = alert_history
      @payload = payload

      mail(to: Array(recipients), subject: subject_for(payload))
    end

    private

    def subject_for(payload)
      "[SolidObserver] #{payload[:event_type]} — #{payload[:rule_name]}"
    end
  end
end
