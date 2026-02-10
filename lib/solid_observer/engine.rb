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
        return if SolidObserver.config.realtime_mode?

        db_config = ActiveRecord::Base.configurations.configs_for(
          env_name: Rails.env,
          name: "solid_observer_queue"
        )

        return unless db_config

        connection_config = {
          database: {writing: :solid_observer_queue, reading: :solid_observer_queue}
        }

        SolidObserver::BaseEvent.connects_to(**connection_config)
        SolidObserver::BaseMetric.connects_to(**connection_config)
      end

      def activate_subscribers
        logger = Rails.logger

        if SolidObserver.config.realtime_mode?
          logger.info "[SolidObserver] Starting in real-time mode (no persistence)"
        elsif !table_exists?("solid_observer_queue_events")
          logger.info "[SolidObserver] Tables not found. Run: rails solid_observer:install:migrations && rails db:migrate"
          return
        else
          logger.info "[SolidObserver] Activating event subscribers"
        end

        Subscriber.subscribe!
      rescue ActiveRecord::NoDatabaseError
        logger.info "[SolidObserver] Database not ready yet. Skipping subscriber activation."
      end

      private

      def table_exists?(table_name)
        ActiveRecord::Base.connection.table_exists?(table_name)
      end
    end

    config.before_initialize do
      Engine.check_solid_queue_availability
    end

    config.after_initialize do
      Engine.configure_database_connection
      Engine.activate_subscribers
    end
  end
end
