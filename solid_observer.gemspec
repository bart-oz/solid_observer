# frozen_string_literal: true

require_relative "lib/solid_observer/version"

Gem::Specification.new do |spec|
  spec.name = "solid_observer"
  spec.version = SolidObserver::VERSION
  spec.authors = ["BartOz"]
  spec.email = ["bartek.ozdoba@gmail.com"]
  spec.summary = "Observability for the Rails 8's Solid Stack"
  spec.description = "Production-grade observability for Rails 8's Solid Stack. Monitor ActiveJob performance, track queue metrics, and debug issues with zero external dependencies. Built-in CLI, retention policies, and APM integrations."
  spec.homepage = "https://solid.observer"
  spec.license = "MIT"
  spec.files = Dir["lib/**/*", "app/**/*", "db/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md", "bin/*"]
  spec.require_paths = ["lib"]
  spec.bindir = "bin"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = "https://solid.observer"
  spec.metadata["source_code_uri"] = "https://github.com/bart-oz/solid_observer"
  spec.metadata["changelog_uri"] = "https://github.com/bart-oz/solid_observer/blob/main/CHANGELOG.md"

  spec.required_ruby_version = ">= #{SolidObserver::RUBY_MINIMUM_VERSION}"
  spec.add_dependency "rails", ">= #{SolidObserver::RAILS_MINIMUM_VERSION}"
  spec.add_dependency "concurrent-ruby", ">= 1.3.1"
  spec.metadata["rubygems_mfa_required"] = "true"
end
