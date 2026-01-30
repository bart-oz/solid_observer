# frozen_string_literal: true

module SolidObserver
  class Engine < ::Rails::Engine
    isolate_namespace SolidObserver

    class << self
      def check_solid_queue_availability
        return if defined?(SolidQueue)

        Rails.logger.warn "[SolidObserver] SolidQueue not detected. Queue observability features will be limited."
      end

      def configure_database_connection
        db_config = ActiveRecord::Base.configurations.configs_for(
          env_name: Rails.env,
          name: "solid_observer_queue"
        )

        return unless db_config

        SolidObserver::BaseEvent.connects_to database: {
          writing: :solid_observer_queue,
          reading: :solid_observer_queue
        }
      end

      def check_and_activate_subscribers
        logger = Rails.logger

        if ActiveRecord::Base.connection.table_exists?("solid_observer_queue_events")
          logger.info "[SolidObserver] Tables detected, activating event subscribers"
        else
          logger.info "[SolidObserver] Tables not found. Run migrations: rails solid_observer:install:migrations && rails db:migrate"
        end
      rescue ActiveRecord::NoDatabaseError
        logger.info "[SolidObserver] Database not ready yet. Skipping subscriber activation."
      end
    end

    config.before_initialize do
      Engine.check_solid_queue_availability
    end

    config.after_initialize do
      Engine.configure_database_connection
      Engine.check_and_activate_subscribers
    end
  end
end
