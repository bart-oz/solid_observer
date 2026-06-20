# frozen_string_literal: true

module SolidObserver
  module Services
    class CableOperations
      MESSAGES = {
        trim: {
          success: "Expired/trimmable Solid Cable messages trimmed.",
          failure: "Cable trim failed. No raw Cable payloads or adapter details are shown. Use solid_observer:cable:trim if the problem continues."
        }.freeze,
        unavailable: "Cable controls are unavailable because Solid Cable support is disabled or not detected."
      }.freeze

      class << self
        def available?
          new.available?
        end

        def trim
          new.trim
        end

        def message(operation, key = nil)
          return MESSAGES.fetch(:unavailable) if operation == :unavailable

          MESSAGES.fetch(operation).fetch(key)
        end

        def unavailable_message
          message(:unavailable)
        end
      end

      def available?
        SolidObserver.config.solid_cable_enabled? && !!defined?(::SolidCable::Message)
      end

      def trim
        messages = self.class
        return {ok: false, message: messages.unavailable_message} unless available?

        perform_operation(
          :trim,
          success_message: messages.message(:trim, :success),
          failure_message: messages.message(:trim, :failure)
        ) do
          trim_cable_messages
        end
      end

      private

      def trim_cable_messages
        if defined?(::SolidCable::TrimJob)
          ::SolidCable::TrimJob.perform_now
        else
          ::SolidCable::Message.trimmable.delete_all
        end
      end

      def perform_operation(name, success_message:, failure_message:)
        yield
        {ok: true, message: success_message}
      rescue => error
        log_failure(name, error)
        {ok: false, message: failure_message}
      end

      def log_failure(name, error)
        Rails.logger&.warn("[SolidObserver] Cable #{name} failed: #{error.class}")
      end
    end
  end
end
