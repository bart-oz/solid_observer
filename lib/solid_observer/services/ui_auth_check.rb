# frozen_string_literal: true

module SolidObserver
  module Services
    # Logs a boot-time WARNING when the Web UI's HTTP Basic Auth is misconfigured.
    #
    # No-ops when the UI is disabled or both credentials are set. Otherwise logs
    # one of two warnings: "no auth configured" (neither credential set) or
    # "auth misconfigured" (exactly one set, naming the missing one).
    #
    # The UI ships fail-open on partial credentials — see
    # SolidObserver::ApplicationController#authenticate.
    class UiAuthCheck
      def self.call(config:, logger: Rails.logger)
        new(config, logger).call
      end

      def initialize(config, logger)
        @config = config
        @logger = logger
      end

      def call
        return unless config.ui_enabled

        warning = warning_message
        logger.warn(warning) if warning
      end

      private

      attr_reader :config, :logger

      def warning_message
        return nil if both_credentials_present?
        return no_auth_warning if neither_credential_present?

        partial_auth_warning
      end

      def both_credentials_present?
        config.ui_username.present? && config.ui_password.present?
      end

      def neither_credential_present?
        config.ui_username.blank? && config.ui_password.blank?
      end

      def no_auth_warning
        "[SolidObserver] WARNING: UI is enabled with no authentication configured. " \
          "Set config.ui_username and config.ui_password."
      end

      def partial_auth_warning
        set, missing = partial_credential_names
        "[SolidObserver] WARNING: UI authentication is misconfigured — #{set} is set but #{missing} is missing/nil. " \
          "The UI will ship UNAUTHENTICATED until both are configured. Set both credentials, or unset both to silence this warning."
      end

      def partial_credential_names
        config.ui_username.present? ? %w[ui_username ui_password] : %w[ui_password ui_username]
      end
    end
  end
end
