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
      :ui_username,
      :ui_password

    # Observer Settings
    attr_accessor :observe_queue

    # Observer Settings (planned for a future release)
    # @note Cache and Cable observers are not yet implemented
    attr_accessor :observe_cache,
      :observe_cable,
      :cache_sampling_rate

    # Retention Settings
    attr_accessor :event_retention

    # Retention Settings (planned for a future release)
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
      :flush_interval,
      :max_buffer_size,
      :buffer_overflow_strategy,
      :filter_cache_ttl

    # Correlation Settings
    attr_accessor :correlation_id_generator

    def initialize
      @ui_enabled, @ui_base_controller, @ui_username, @ui_password,
        @storage_mode, @observe_queue, @observe_cache, @observe_cable,
        @event_retention, @metrics_retention, @max_db_size, @warning_threshold,
        @sampling_rate, @cache_sampling_rate, @buffer_size, @flush_interval,
        @max_buffer_size, @buffer_overflow_strategy, @filter_cache_ttl,
        @correlation_id_generator = !production?, "::ApplicationController", nil, nil,
          :persistence, true, false, false,
          30.days, 90.days, 1.gigabyte, 0.8,
          1.0, 0.1, 1000, 10.seconds,
          10_000, :drop_old, 1.minute,
          nil
    end

    STORAGE_MODES = %i[persistence realtime].freeze
    BUFFER_OVERFLOW_STRATEGIES = %i[drop_old drop_new].freeze

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

    def solid_queue_available?
      !!defined?(::SolidQueue)
    end

    def solid_cache_available?
      !!defined?(::SolidCache)
    end

    def solid_queue_enabled?
      observe_queue
    end

    def solid_cache_enabled?
      observe_cache && solid_cache_available?
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
      if defined?(@max_buffer_size) && value > @max_buffer_size
        raise ArgumentError, "buffer_size must be <= max_buffer_size"
      end

      @buffer_size = value
    end

    def flush_interval=(value)
      validate_positive_numeric!(:flush_interval, value)
      @flush_interval = value
    end

    def max_buffer_size=(value)
      validate_positive_integer!(:max_buffer_size, value)
      if defined?(@buffer_size) && value < @buffer_size
        raise ArgumentError, "max_buffer_size must be >= buffer_size"
      end

      @max_buffer_size = value
    end

    def buffer_overflow_strategy=(value)
      value = value.to_sym
      unless BUFFER_OVERFLOW_STRATEGIES.include?(value)
        raise ArgumentError, "buffer_overflow_strategy must be :drop_old or :drop_new"
      end

      @buffer_overflow_strategy = value
    end

    def filter_cache_ttl=(value)
      validate_positive_numeric!(:filter_cache_ttl, value)
      @filter_cache_ttl = value
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
