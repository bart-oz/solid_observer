# frozen_string_literal: true

ENV["RAILS_ENV"] = "test"
require_relative "dummy/config/environment"
require "capybara/rspec"

Capybara.app = Rails.application

# When spec_helper is auto-loaded before feature_helper (via .rspec --require spec_helper),
# the engine's URL helpers may not be properly included in controllers because controllers
# were loaded before Rails.application drew the routes. Re-include them explicitly.
SolidObserver::ApplicationController.include SolidObserver::Engine.routes.url_helpers
SolidObserver::ApplicationController.helper SolidObserver::Engine.routes.url_helpers
SolidObserver::ApplicationController.helper SolidObserver::ApplicationHelper

RSpec.configure do |config|
  config.include Capybara::DSL, type: :feature

  config.before(:suite) do
    conn = SolidObserver::QueueEvent.connection

    unless conn.table_exists?(:solid_observer_queue_events)
      conn.create_table :solid_observer_queue_events do |t|
        t.string :event_type, null: false, limit: 50
        t.string :job_class, limit: 100
        t.string :queue_name, limit: 50
        t.string :correlation_id, limit: 64
        t.text :metadata
        t.float :duration
        t.datetime :recorded_at, null: false
        t.index :recorded_at
        t.index :event_type
        t.index :job_class
        t.index :queue_name
      end
    end

    unless conn.table_exists?(:solid_observer_storage_info)
      conn.create_table :solid_observer_storage_info do |t|
        t.integer :event_count, default: 0
        t.integer :db_size_bytes, default: 0
        t.datetime :recorded_at, null: false
        t.index :recorded_at
      end
    end
  end

  config.after(type: :feature) { SolidObserver.reset_configuration! }
end
