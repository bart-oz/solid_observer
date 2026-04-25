# frozen_string_literal: true

module SolidObserver
  class Engine < ::Rails::Engine
    isolate_namespace SolidObserver

    class << self
      def check_solid_queue_availability
        return if defined?(SolidQueue)

        Rails.logger.warn "[SolidObserver] SolidQueue not detected. Queue observability features will be limited."
      end

      def check_ui_authentication
        config = SolidObserver.config
        return unless config.ui_enabled
        return if config.ui_username.present?

        Rails.logger.warn "[SolidObserver] WARNING: UI is enabled with no authentication configured. " \
          "Set config.ui_username and config.ui_password."
      end

      def configure_database_connection
        return if SolidObserver.config.realtime_mode?
        return unless queue_db_config

        connect_observer_models
      end

      def activate_subscribers
        return activate_subscribers_in_realtime if SolidObserver.config.realtime_mode?
        return if activation_skipped_for_table_status?

        Rails.logger.info "[SolidObserver] Activating event subscribers"
        Subscriber.subscribe!
      end

      private

      def queue_db_config
        ActiveRecord::Base.configurations.configs_for(
          env_name: Rails.env,
          name: "solid_observer_queue"
        )
      end

      def connect_observer_models
        connection_config = {
          database: {writing: :solid_observer_queue, reading: :solid_observer_queue}
        }

        SolidObserver::BaseEvent.connects_to(**connection_config)
        SolidObserver::BaseMetric.connects_to(**connection_config)
      end

      def activate_subscribers_in_realtime
        Rails.logger.info "[SolidObserver] Starting in real-time mode (no persistence)"
        Subscriber.subscribe!
      end

      def activation_skipped_for_table_status?
        case table_status("solid_observer_queue_events")
        when :absent
          log_activation_skip("Tables not found. Run: rails solid_observer:install:migrations && rails db:migrate")
          true
        when :unknown
          log_activation_skip("Database not reachable at boot. Skipping subscriber activation.")
          true
        else
          false
        end
      end

      def log_activation_skip(message)
        Rails.logger.info("[SolidObserver] #{message}")
      end

      def table_status(table_name)
        pool = SolidObserver::BaseEvent.connection_pool

        return :present if cached_data_source_exists?(pool, table_name)

        data_source_exists_in_db?(pool, table_name) ? :present : :absent
      rescue *boot_connection_errors
        :unknown
      end

      def cached_data_source_exists?(pool, table_name)
        cache = pool.schema_cache
        cache.data_source_exists?(pool, table_name)
      rescue ArgumentError
        cache.data_source_exists?(table_name)
      end

      def data_source_exists_in_db?(pool, table_name)
        pool.with_connection { |connection| connection.data_source_exists?(table_name) }
      end

      def boot_connection_errors
        [
          ActiveRecord::NoDatabaseError,
          ActiveRecord::ConnectionNotEstablished,
          ActiveRecord::StatementInvalid,
          *([PG::ConnectionBad] if defined?(PG::ConnectionBad)),
          *([Mysql2::Error::ConnectionError] if defined?(Mysql2::Error::ConnectionError)),
          *([SQLite3::CantOpenException] if defined?(SQLite3::CantOpenException))
        ]
      end
    end

    config.before_initialize do
      Engine.check_solid_queue_availability
    end

    config.after_initialize do
      Engine.configure_database_connection
      Engine.activate_subscribers
      Engine.check_ui_authentication
    end
  end
end
