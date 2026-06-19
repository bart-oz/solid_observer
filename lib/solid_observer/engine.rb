# frozen_string_literal: true

module SolidObserver
  class Engine < ::Rails::Engine
    isolate_namespace SolidObserver

    middleware.use ActionDispatch::Cookies
    middleware.use ActionDispatch::Session::CookieStore, key: "_solid_observer_session"
    middleware.use ActionDispatch::Flash

    class << self
      def check_solid_queue_availability
        return if defined?(::SolidQueue)

        Rails.logger.warn "[SolidObserver] SolidQueue not detected. Queue observability features will be limited."
      end

      def check_solid_cache_availability
        return if defined?(::SolidCache)
        return unless SolidObserver.config.observe_cache

        Rails.logger.warn "[SolidObserver] SolidCache not detected. Cache observability features will be disabled."
      end

      def check_solid_cable_availability
        return if defined?(::SolidCable)
        return unless SolidObserver.config.observe_cable

        Rails.logger.warn "[SolidObserver] SolidCable not detected. Cable observability features will be disabled."
      end

      def check_ui_authentication
        Services::UiAuthCheck.call(config: SolidObserver.config)
      end

      def configure_database_connection
        return if SolidObserver.config.realtime_mode?
        return unless queue_db_config

        connect_observer_models
      end

      def activate_subscribers
        return activate_subscribers_in_realtime if SolidObserver.config.realtime_mode?

        Rails.logger.info "[SolidObserver] Activating event subscribers"
        activate_queue_subscriber
        activate_cache_subscriber
        activate_cable_subscriber
      end

      private

      def queue_db_config
        return unless active_record_available?

        ActiveRecord::Base.configurations.configs_for(
          env_name: Rails.env,
          name: "solid_observer_queue"
        )
      end

      def connect_observer_models
        connection_config = {
          database: {writing: :solid_observer_queue, reading: :solid_observer_queue}
        }

        SolidObserver::BaseRecord.connects_to(**connection_config)
      end

      def active_record_available?
        defined?(::ActiveRecord::Base)
      end

      def activate_subscribers_in_realtime
        Rails.logger.info "[SolidObserver] Starting in real-time mode (no persistence)"
        Subscriber.subscribe! if should_activate_queue_subscriber?
        CacheSubscriber.subscribe! if should_activate_cache_subscriber?
        CableSubscriber.subscribe! if should_activate_cable_subscriber?
      end

      def activate_queue_subscriber
        activate_subscriber_for_table("solid_observer_queue_events", Subscriber) if should_activate_queue_subscriber?
      end

      def activate_cache_subscriber
        activate_subscriber_for_table("solid_observer_cache_events", CacheSubscriber) if should_activate_cache_subscriber?
      end

      def activate_cable_subscriber
        activate_subscriber_for_table("solid_observer_cable_events", CableSubscriber) if should_activate_cable_subscriber?
      end

      def activate_subscriber_for_table(table_name, subscriber)
        case table_status(table_name)
        when :absent
          log_activation_skip("Tables not found (missing: #{table_name}). Run: rails solid_observer:install:migrations && rails db:migrate")
        when :unknown
          log_activation_skip("Database not reachable at boot. Skipping subscriber activation.")
        else
          subscriber.subscribe!
        end
      end

      def should_activate_queue_subscriber?
        SolidObserver.config.solid_queue_enabled?
      end

      def should_activate_cache_subscriber?
        SolidObserver.config.solid_cache_enabled?
      end

      def should_activate_cable_subscriber?
        SolidObserver.config.solid_cable_enabled?
      end

      def log_activation_skip(message)
        Rails.logger.info("[SolidObserver] #{message}")
      end

      def table_status(table_name)
        return :unknown unless active_record_available?

        data_source_status(table_name)
      rescue *boot_connection_errors
        :unknown
      end

      def data_source_status(table_name)
        pool = SolidObserver::BaseRecord.connection_pool

        return :present if cached_data_source_exists?(pool, table_name)

        data_source_exists_in_db?(pool, table_name) ? :present : :absent
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
        return [] unless active_record_available?

        [
          ActiveRecord::NoDatabaseError,
          ActiveRecord::ConnectionNotEstablished,
          ActiveRecord::StatementInvalid,
          *([PG::ConnectionBad] if defined?(PG::ConnectionBad)),
          *([Mysql2::Error::ConnectionError] if defined?(Mysql2::Error::ConnectionError)),
          *([Trilogy::Error] if defined?(Trilogy::Error)),
          *([SQLite3::CantOpenException] if defined?(SQLite3::CantOpenException))
        ]
      end
    end

    config.before_initialize do
      Engine.check_solid_queue_availability
      Engine.check_solid_cache_availability
      Engine.check_solid_cable_availability
    end

    config.after_initialize do
      Engine.configure_database_connection
      Engine.activate_subscribers
      Engine.check_ui_authentication
    end
  end
end
