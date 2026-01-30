# frozen_string_literal: true

require "active_support/core_ext/numeric/time"
require "active_support/core_ext/numeric/bytes"

module SolidObserver
  # Configuration options for SolidObserver.
  #
  # @example Basic configuration
  #   SolidObserver.configure do |config|
  #     config.event_retention = 14.days
  #     config.sampling_rate = 0.5
  #   end
  class Configuration
    # UI Settings
    attr_accessor :ui_enabled,
      :ui_base_controller,
      :http_basic_auth_enabled,
      :http_basic_auth_user,
      :http_basic_auth_password

    # Observer Settings
    attr_accessor :observe_queue

    # Observer Settings (planned for v0.2.0)
    # @note Cache and Cable observers are not yet implemented
    attr_accessor :observe_cache,
      :observe_cable,
      :cache_sampling_rate

    # Retention Settings
    attr_accessor :event_retention

    # Retention Settings (planned for v0.2.0)
    # @note Metrics cleanup is not yet implemented
    attr_accessor :metrics_retention

    # Storage Settings
    attr_accessor :max_db_size,
      :warning_threshold

    # Performance Settings
    attr_accessor :sampling_rate,
      :buffer_size,
      :flush_interval

    # Correlation Settings
    attr_accessor :correlation_id_generator

    def initialize
      # UI defaults
      @ui_enabled = !production?
      @ui_base_controller = "::ApplicationController"
      @http_basic_auth_enabled = false
      @http_basic_auth_user = nil
      @http_basic_auth_password = nil

      # Observer defaults
      @observe_queue = true
      @observe_cache = false  # v0.2.0
      @observe_cable = false  # v0.2.0

      # Retention defaults
      @event_retention = 30.days
      @metrics_retention = 90.days  # v0.2.0

      # Storage defaults
      @max_db_size = 1.gigabyte
      @warning_threshold = 0.8

      # Performance defaults
      @sampling_rate = 1.0
      @cache_sampling_rate = 0.1  # v0.2.0
      @buffer_size = 1000
      @flush_interval = 10.seconds

      # Correlation defaults
      @correlation_id_generator = nil
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
