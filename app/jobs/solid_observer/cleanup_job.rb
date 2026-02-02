# frozen_string_literal: true

module SolidObserver
  class CleanupJob < ActiveJob::Base
    queue_as :default
    retry_on StandardError, wait: :exponentially_longer, attempts: 3

    def perform
      Services::CleanupStorage.call
    end
  end
end
