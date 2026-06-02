# frozen_string_literal: true

require_relative "database_size"

module SolidObserver
  module Services
    class StorageInfoSnapshot
      Component = Struct.new(:key, :label, :table_name, :record_label, :model, :enabled, keyword_init: true) do
        def enabled?
          enabled.call
        end

        def solid_cache?
          key == "solid_cache"
        end

        def storage_model
          model.call
        end

        def data_source_exists?(connection)
          connection.data_source_exists?(table_name)
        end

        def database_size(connection)
          DatabaseSize.call(connection: connection, table_name: table_name)
        end

        def snapshot
          return unless enabled?
          return unavailable_snapshot(reason: "SolidCache is unavailable") if unavailable_solid_cache?

          existing_data_source_snapshot
        rescue *StorageInfoSnapshot::CONNECTION_ERRORS
          unavailable_snapshot(reason: "Storage unavailable")
        end

        def available_snapshot(db_size_bytes:, event_count:)
          {
            component: key,
            label: label,
            available: true,
            db_size_bytes: db_size_bytes,
            event_count: event_count,
            record_label: record_label,
            recorded_at: Time.current,
            unavailable_reason: nil
          }
        end

        def unavailable_snapshot(reason:)
          {
            component: key,
            label: label,
            available: false,
            db_size_bytes: nil,
            event_count: nil,
            record_label: record_label,
            recorded_at: nil,
            unavailable_reason: reason
          }
        end

        private

        def unavailable_solid_cache?
          solid_cache? && !defined?(::SolidCache::Record)
        end

        def existing_data_source_snapshot
          record_model = storage_model
          connection = record_model.connection
          return unavailable_snapshot(reason: "Table unavailable") unless data_source_exists?(connection)

          available_snapshot(
            db_size_bytes: database_size(connection),
            event_count: record_model.count
          )
        end
      end

      COMPONENTS = [
        Component.new(
          key: "queue_observer",
          label: "Queue observer",
          table_name: "solid_observer_queue_events",
          record_label: "observer events",
          model: -> { SolidObserver::QueueEvent },
          enabled: -> { SolidObserver.config.solid_queue_enabled? }
        ),
        Component.new(
          key: "cache_observer",
          label: "Cache observer",
          table_name: "solid_observer_cache_events",
          record_label: "observer events",
          model: -> { SolidObserver::CacheEvent },
          enabled: -> { SolidObserver.config.solid_cache_enabled? }
        ),
        Component.new(
          key: "solid_cache",
          label: "SolidCache",
          table_name: "solid_cache_entries",
          record_label: "cache rows",
          model: -> { ::SolidCache::Record },
          enabled: -> { SolidObserver.config.solid_cache_enabled? }
        )
      ].freeze

      CONNECTION_ERRORS = [
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::StatementInvalid,
        *([PG::ConnectionBad] if defined?(PG::ConnectionBad)),
        *([Mysql2::Error::ConnectionError] if defined?(Mysql2::Error::ConnectionError)),
        *([SQLite3::CantOpenException] if defined?(SQLite3::CantOpenException))
      ].freeze

      def self.call
        new.call
      end

      def call
        COMPONENTS.filter_map(&:snapshot)
      end
    end
  end
end
