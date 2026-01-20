# frozen_string_literal: true

require "simplecov"

SimpleCov.start do
  add_filter "/spec/"
  add_filter "/lib/solid_observer/version.rb"
  track_files "lib/**/*.rb"
  minimum_coverage 80
  minimum_coverage_by_file 70
end

require "bundler/setup"
require "rspec"
require "rails"
require "action_controller/railtie"
require "active_record/railtie"
require "active_job/railtie"

ENV["RAILS_ENV"] = "test"
Rails.env = ActiveSupport::StringInquirer.new("test")

require_relative "../lib/solid_observer"

class ApplicationJob < ActiveJob::Base
end

ActiveRecord::Base.configurations = {
  "test" => {
    "solid_observer_queue" => {
      "adapter" => "sqlite3",
      "database" => ":memory:"
    }
  }
}
ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")

Dir[File.join(__dir__, "../app/models/**/*.rb")].each { |f| require f }
Dir[File.join(__dir__, "../app/jobs/**/*.rb")].each { |f| require f }

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  config.mock_with :rspec do |mocks|
    mocks.verify_partial_doubles = true
  end

  config.shared_context_metadata_behavior = :apply_to_host_groups
  config.filter_run_when_matching :focus
  config.example_status_persistence_file_path = "spec/.rspec_status"
  config.disable_monkey_patching!
  config.warnings = true

  if config.files_to_run.one?
    config.default_formatter = "doc"
  end

  config.order = :random
  Kernel.srand config.seed
end
