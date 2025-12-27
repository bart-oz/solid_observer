# frozen_string_literal: true

require "active_support/core_ext/numeric/time"

module SolidObserver
  class Configuration
    attr_accessor :ui_enabled,
      :ui_base_controller,
      :http_basic_auth_enabled,
      :http_basic_auth_user,
      :http_basic_auth_password,
      :observe_queue,
      :observe_cache,
      :observe_cable,
      :event_retention,
      :metrics_retention,
      :sampling_rate,
      :cache_sampling_rate,
      :buffer_size,
      :flush_interval

    def initialize
      @ui_enabled = !production?
      @ui_base_controller = "::ApplicationController"
      @http_basic_auth_enabled = false
      @http_basic_auth_user = nil
      @http_basic_auth_password = nil
      @observe_queue = true
      @observe_cache = true
      @observe_cable = true
      @event_retention = 30.days
      @metrics_retention = 90.days
      @sampling_rate = 1.0
      @cache_sampling_rate = 0.1
      @buffer_size = 1000
      @flush_interval = 10.seconds
    end

    private

    def production?
      defined?(Rails) && Rails.env.production?
    end
  end
end
