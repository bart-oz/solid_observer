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
    attr_accessor :max_db_size

    # Storage Mode
    attr_reader :storage_mode

    # Performance Settings (with validation)
    attr_reader :sampling_rate,
      :warning_threshold,
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

      # Storage mode
      @storage_mode = :persistence

      # Observer defaults
      @observe_queue = true
      @observe_cache = false
      @observe_cable = false

      # Retention defaults
      @event_retention = 30.days
      @metrics_retention = 90.days

      # Storage defaults
      @max_db_size = 1.gigabyte
      @warning_threshold = 0.8

      # Performance defaults
      @sampling_rate = 1.0
      @cache_sampling_rate = 0.1
      @buffer_size = 1000
      @flush_interval = 10.seconds

      # Correlation defaults
      @correlation_id_generator = nil
    end

    STORAGE_MODES = %i[persistence realtime].freeze

    def storage_mode=(value)
      value = value.to_sym
      raise ArgumentError, "storage_mode must be :persistence or :realtime" unless STORAGE_MODES.include?(value)

      @storage_mode = value
    end

    def persistence_mode?
      @storage_mode == :persistence
    end

    def realtime_mode?
      @storage_mode == :realtime
    end

    def sampling_rate=(value)
      validate_rate!(:sampling_rate, value)
      @sampling_rate = value
    end

    def warning_threshold=(value)
      validate_rate!(:warning_threshold, value)
      @warning_threshold = value
    end

    def buffer_size=(value)
      validate_positive_integer!(:buffer_size, value)
      @buffer_size = value
    end

    def flush_interval=(value)
      validate_positive_numeric!(:flush_interval, value)
      @flush_interval = value
    end

    private

    def validate_rate!(name, value)
      unless value.is_a?(Numeric) && value >= 0.0 && value <= 1.0
        raise ArgumentError, "#{name} must be a number between 0.0 and 1.0"
      end
    end

    def validate_positive_integer!(name, value)
      unless value.is_a?(Integer) && value > 0
        raise ArgumentError, "#{name} must be a positive integer"
      end
    end

    def validate_positive_numeric!(name, value)
      unless value.is_a?(Numeric) && value > 0
        raise ArgumentError, "#{name} must be a positive number"
      end
    end

    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
