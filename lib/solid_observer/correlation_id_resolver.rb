# frozen_string_literal: true

require "securerandom"

module SolidObserver
  class CorrelationIdResolver
    def self.resolve(event)
      new(event).resolve
    end

    def initialize(event)
      @event = event
    end

    def resolve
      custom_generator_result.presence ||
        job_id_result.presence ||
        thread_correlation_id.presence ||
        SecureRandom.uuid
    end

    private

    def custom_generator_result
      call_custom_generator if custom_generator_configured?
    end

    def job_id_result
      extract_job_id if job_event?
    end

    def thread_correlation_id
      Thread.current[:solid_observer_correlation_id]
    end

    def custom_generator_configured?
      SolidObserver.config.correlation_id_generator.present?
    end

    def call_custom_generator
      custom_generator_value.presence
    end

    def log_generator_error(exception)
      return unless defined?(Rails) && Rails.logger
      Rails.logger.warn "[SolidObserver] Custom correlation_id_generator failed: #{exception.message}"
    end

    def job_event?
      @event.payload[:job]&.job_id.present?
    end

    def extract_job_id
      @event.payload[:job].job_id
    end

    def custom_generator_value
      SolidObserver.config.correlation_id_generator.call
    rescue => e
      log_generator_error(e)
      nil
    end
  end
end
