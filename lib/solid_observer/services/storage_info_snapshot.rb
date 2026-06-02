# frozen_string_literal: true

require_relative "database_size"

module SolidObserver
  module Services
    class StorageInfoSnapshot
      Component = Struct.new(:key, :label, :record_label, :model, :enabled, keyword_init: true) do
        def enabled?
          enabled.call
        end

        def solid_cache?
          key == "solid_cache"
        end

        def storage_model
          model.call
        end

        def data_source_exists?(connection, table_name)
          connection.data_source_exists?(table_name)
        end

        def database_size(connection, table_name)
          DatabaseSize.call(connection: connection, table_name: table_name)
        end

        def snapshot
          return unless enabled?
          return unavailable_snapshot(reason: "SolidCache is unavailable") if unavailable_solid_cache?

          existing_data_source_snapshot
        rescue *StorageInfoSnapshot::CONNECTION_ERRORS, TypeError
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
          solid_cache? && !defined?(::SolidCache::Entry)
        end

        def existing_data_source_snapshot
          record_model = storage_model
          connection = record_model.connection
          table_name = record_model.table_name.to_s
          return table_unavailable_snapshot if table_name.empty? || !data_source_exists?(connection, table_name)

          available_snapshot(
            db_size_bytes: database_size(connection, table_name),
            event_count: record_model.count
          )
        end

        def table_unavailable_snapshot
          unavailable_snapshot(reason: "Table unavailable")
        end
      end

      COMPONENTS = [
        Component.new(
          key: "queue_observer",
          label: "Queue observer",
          record_label: "observer events",
          model: -> { SolidObserver::QueueEvent },
          enabled: -> { SolidObserver.config.solid_queue_enabled? }
        ),
        Component.new(
          key: "cache_observer",
          label: "Cache observer",
          record_label: "observer events",
          model: -> { SolidObserver::CacheEvent },
          enabled: -> { SolidObserver.config.solid_cache_enabled? }
        ),
        Component.new(
          key: "solid_cache",
          label: "SolidCache",
          record_label: "cache rows",
          model: -> { ::SolidCache::Entry },
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
