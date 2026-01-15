# frozen_string_literal: true

require_relative "solid_observer/version"
require_relative "solid_observer/configuration"
require_relative "solid_observer/correlation_id_resolver"
require_relative "solid_observer/base_event" if defined?(ActiveRecord)
require_relative "solid_observer/engine" if defined?(Rails::Engine)

module SolidObserver
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def config
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
