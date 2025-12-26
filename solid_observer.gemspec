# frozen_string_literal: true

require_relative "lib/solid_observer/version"

Gem::Specification.new do |spec|
  spec.name = "solid_observer"
  spec.version = SolidObserver::VERSION
  spec.authors = ["BartOz"]
  spec.email = ["bartek.ozdoba@gmail.com"]
  spec.summary = "Observe your Solid Stack like a pro!"
  spec.description = "SolidObserver is a production-grade observability solution for Rails 8's Solid Stack (Solid Queue, Solid Cache, Solid Cable). It provides unified monitoring, health metrics, and debugging tools across all three Solid technologies."
  spec.homepage = "https://solid.observer"
  spec.license = "MIT"
  spec.files = Dir["lib/**/*", "README.md", "LICENSE.txt", "CHANGELOG.md", "bin/*"]
  spec.require_paths = ["lib"]
  spec.bindir = "bin"

  spec.metadata["allowed_push_host"] = "https://rubygems.org"
  spec.metadata["homepage_uri"] = "https://solid.observer"
  spec.metadata["source_code_uri"] = "https://github.com/bart-oz/solid_observer"
  spec.metadata["changelog_uri"] = "https://github.com/bart-oz/solid_observer/blob/main/CHANGELOG.md"

  spec.required_ruby_version = ">= #{SolidObserver::RUBY_MINIMUM_VERSION}"
  spec.add_dependency "rails", ">= #{SolidObserver::RAILS_MINIMUM_VERSION}"
  spec.metadata["rubygems_mfa_required"] = "true"
end
