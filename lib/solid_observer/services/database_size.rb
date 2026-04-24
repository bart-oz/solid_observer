# frozen_string_literal: true

module SolidObserver
  module Services
    # Returns bytes used by solid_observer_queue_events across supported adapters.
    #
    # SQLite uses whole-database page accounting; PostgreSQL and MySQL/Trilogy
    # use table + index size from adapter-native system functions.
    class DatabaseSize
      TABLE_NAME = "solid_observer_queue_events"

      def self.call(connection:)
        new(connection).call
      end

      def initialize(connection)
        @connection = connection
      end

      def call
        case adapter_key
        when :sqlite then sqlite_size
        when :postgresql then postgresql_size
        when :mysql then mysql_size
        else
          log_unknown_adapter
          nil
        end
      rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished => e
        Rails.logger&.warn("[SolidObserver] DatabaseSize query failed: #{e.message}")
        nil
      end

      private

      attr_reader :connection

      def adapter_key
        case connection.adapter_name.to_s.downcase
        when /sqlite/ then :sqlite
        when /postgres|postgis/ then :postgresql
        when "mysql2", "trilogy" then :mysql
        end
      end

      def sqlite_size
        connection.query_value("SELECT pragma_page_count() * pragma_page_size()")&.to_i
      end

      def postgresql_size
        quoted_table = connection.quote(TABLE_NAME)
        connection.query_value("SELECT pg_total_relation_size(#{quoted_table})")&.to_i
      end

      def mysql_size
        quoted_table = connection.quote(TABLE_NAME)

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
    end
  end
end
