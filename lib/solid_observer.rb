# frozen_string_literal: true

require_relative "solid_observer/version"
require_relative "solid_observer/configuration"

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
