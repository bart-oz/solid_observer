# frozen_string_literal: true

module SolidObserver
  class EvaluateAlertsJob < ActiveJob::Base
    queue_as :default
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform
      Services::EvaluateAlerts.call
    end
  end
end
