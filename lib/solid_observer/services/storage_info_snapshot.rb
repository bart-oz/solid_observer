# frozen_string_literal: true

require_relative "database_size"

module SolidObserver
  module Services
    class StorageInfoSnapshot
      COMPONENTS = [
        {
          key: "queue_observer",
          label: "Queue observer",
          table_name: "solid_observer_queue_events",
          record_label: "observer events",
          model: -> { SolidObserver::QueueEvent },
          enabled: -> { SolidObserver.config.solid_queue_enabled? }
        },
        {
          key: "cache_observer",
          label: "Cache observer",
          table_name: "solid_observer_cache_events",
          record_label: "observer events",
          model: -> { SolidObserver::CacheEvent },
          enabled: -> { SolidObserver.config.solid_cache_enabled? }
        },
        {
          key: "solid_cache",
          label: "SolidCache",
          table_name: "solid_cache_entries",
          record_label: "cache rows",
          model: -> { ::SolidCache::Record },
          enabled: -> { SolidObserver.config.solid_cache_enabled? }
        }
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
        COMPONENTS.filter_map do |component|
          build_component_snapshot(component)
        end
      end

      private

      def build_component_snapshot(component)
        key = component[:key]
        label = component[:label]
        table_name = component[:table_name]
        record_label = component[:record_label]

        return unless component[:enabled].call
        return unavailable_component(key: key, label: label, record_label: record_label, reason: "SolidCache is unavailable") if solid_cache_unavailable?(key)

        model = component[:model].call
        connection = model.connection
        return unavailable_component(key: key, label: label, record_label: record_label, reason: "Table unavailable") unless connection.data_source_exists?(table_name)

        {
          component: key,
          label: label,
          available: true,
          db_size_bytes: DatabaseSize.call(connection: connection, table_name: table_name),
          event_count: model.count,
          record_label: record_label,
          recorded_at: Time.current,
          unavailable_reason: nil
        }
      rescue *CONNECTION_ERRORS
        unavailable_component(key: key, label: label, record_label: record_label, reason: "Storage unavailable")
      end

      def solid_cache_unavailable?(key)
        key == "solid_cache" && !defined?(::SolidCache::Record)
      end

      def unavailable_component(key:, label:, record_label:, reason:)
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
    end
  end
end
