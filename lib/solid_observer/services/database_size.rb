# frozen_string_literal: true

module SolidObserver
  module Services
    # Returns bytes used by solid_observer_queue_events across supported adapters.
    #
    # SQLite uses whole-database page accounting; PostgreSQL and MySQL/Trilogy
    # use table + index size from adapter-native system functions.
    class DatabaseSize
      DEFAULT_TABLE_NAME = "solid_observer_queue_events"

      def self.call(connection:, table_name: DEFAULT_TABLE_NAME)
        new(connection, table_name: table_name).call
      end

      def initialize(connection, table_name:)
        @connection = connection
        @table_name = table_name
      end

      def call
        fetch_size
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
        log_query_failure(e.message)
        nil
      end

      private

      attr_reader :connection, :table_name

      def adapter_key
        case connection.adapter_name.to_s.downcase
        when /sqlite/ then :sqlite
        when /postgres|postgis/ then :postgresql
        when "mysql2", "trilogy" then :mysql
        end
      end

      def fetch_size
        case adapter_key
        when :sqlite then sqlite_size
        when :postgresql then postgresql_size
        when :mysql then mysql_size
        else
          unknown_adapter_size
        end
      end

      def unknown_adapter_size
        log_unknown_adapter
        nil
      end

      def sqlite_size
        page_count = connection.query_value("PRAGMA page_count")
        page_size = connection.query_value("PRAGMA page_size")
        return unless page_count && page_size

        page_count.to_i * page_size.to_i
      end

      def postgresql_size
        quoted_table = connection.quote(table_name)
        connection.query_value("SELECT pg_total_relation_size(#{quoted_table})")&.to_i
      end

      def mysql_size
        quoted_table = connection.quote(table_name)

        connection.query_value(<<~SQL)&.to_i
          SELECT COALESCE(data_length + index_length, 0)
          FROM information_schema.tables
          WHERE table_schema = DATABASE()
            AND table_name = #{quoted_table}
        SQL
      end

      def log_unknown_adapter
        Rails.logger&.warn(
          "[SolidObserver] Unknown adapter for DatabaseSize: " \
          "#{connection.adapter_name.inspect} — storage monitoring disabled"
        )
      end

      def log_query_failure(message)
        Rails.logger&.warn("[SolidObserver] DatabaseSize query failed: #{message}")
      end
    end
  end
end
