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
        else
          case table_status("solid_observer_queue_events")
          when :absent
            logger.info "[SolidObserver] Tables not found. Run: rails solid_observer:install:migrations && rails db:migrate"
            return
          when :unknown
            logger.info "[SolidObserver] Database not reachable at boot. Skipping subscriber activation."
            return
          end

          logger.info "[SolidObserver] Activating event subscribers"
        end

        Subscriber.subscribe!
      end

      private

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
    end
  end
end
