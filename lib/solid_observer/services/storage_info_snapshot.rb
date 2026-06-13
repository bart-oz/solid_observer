# frozen_string_literal: true

require_relative "database_size"

module SolidObserver
  module Services
    class StorageInfoSnapshot
      class RecordCount
        def initialize(connection, table_name)
          @connection = connection
          @table_name = table_name
        end

        def solid_cache_count
          case adapter_key
          when :postgresql then postgresql_approximate_count
          when :mysql then mysql_approximate_count
          else
            yield
          end
        end

        private

        attr_reader :connection, :table_name

        def adapter_key
          case connection.adapter_name.to_s.downcase
          when /postgres|postgis/ then :postgresql
          when "mysql2", "trilogy", "mysql" then :mysql
          else
            :other
          end
        end

        def postgresql_approximate_count
          quoted_table = connection.quote(table_name)

          connection.query_value(<<~SQL.squish)&.to_i || 0
            SELECT COALESCE(
              (SELECT reltuples::bigint FROM pg_class WHERE oid = to_regclass(#{quoted_table})),
              0
            )
          SQL
        end

        def mysql_approximate_count
          quoted_table = connection.quote(table_name)

          connection.query_value(<<~SQL)&.to_i || 0
            SELECT COALESCE(table_rows, 0)
            FROM information_schema.tables
            WHERE table_schema = DATABASE()
              AND table_name = #{quoted_table}
          SQL
        end
      end

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
          return unavailable_snapshot(reason: "Table unavailable") unless data_source_available?(connection, table_name)

          available_snapshot(
            db_size_bytes: DatabaseSize.call(connection: connection, table_name: table_name),
            event_count: snapshot_event_count(record_model, connection, table_name)
          )
        end

        def data_source_available?(connection, table_name)
          !table_name.empty? && connection.data_source_exists?(table_name)
        end

        def snapshot_event_count(record_model, connection, table_name)
          record_count = RecordCount.new(connection, table_name)
          exact_count = -> { record_model.count }
          return exact_count.call unless solid_cache?

          record_count.solid_cache_count(&exact_count)
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
