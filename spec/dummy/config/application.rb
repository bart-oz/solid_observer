# frozen_string_literal: true

require_relative "boot"

require "rails/all"

Bundler.require(*Rails.groups)

require "solid_observer"

module Dummy
  class Application < Rails::Application
    config.load_defaults Rails::VERSION::STRING.to_f

    # Dummy app only needs what the engine provides
    config.eager_load = false

    # Use the engine's migrations
    config.paths["db/migrate"] << SolidObserver::Engine.paths["db/migrate"].first

    config.logger = Logger.new($stdout)
    config.logger.level = Logger::INFO

    # Required so engine URL helpers resolve inside the engine layout
    config.action_dispatch.default_headers = {"X-Frame-Options" => "SAMEORIGIN"}
  end
end
