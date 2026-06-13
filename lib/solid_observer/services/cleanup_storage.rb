# frozen_string_literal: true

require_relative "database_size"
require_relative "storage_info_snapshot"

module SolidObserver
  module Services
    class CleanupStorage
      MAINTENANCE_STATEMENT_BUILDERS = {
        "sqlite" => ->(_tables) { ["VACUUM"] },
        "postgresql" => ->(tables) { tables.map { |table_name| "VACUUM ANALYZE #{table_name}" } },
        "mysql2" => ->(tables) { ["OPTIMIZE TABLE #{tables.join(", ")}"] },
        "trilogy" => ->(tables) { ["OPTIMIZE TABLE #{tables.join(", ")}"] }
      }.freeze

      def self.call
        new.call
      end

      def call
        return 0 if SolidObserver.config.realtime_mode?

        post_cleanup(cleanup_counts)
      rescue => error
        handle_cleanup_failure(error)
      end

      private

      def cleanup_counts
        perform_cleanup.tap { record_snapshot_after_cleanup }
      end

      def handle_cleanup_failure(error)
        Rails.logger.error "[SolidObserver] Cleanup failed: #{error.message}"
        raise
      end

      def perform_cleanup
        config = SolidObserver.config
        event_cutoff = config.event_retention.ago

        {
          queue_events: QueueEvent.transaction do
            QueueEvent.where("recorded_at < ?", event_cutoff).delete_all
          end,
          cache_events: delete_telemetry_records(
            SolidObserver::CacheEvent,
            column: :recorded_at,
            cutoff: event_cutoff
          ),
          cache_metrics: delete_telemetry_records(
            SolidObserver::CacheMetric,
            column: :period_start,
            cutoff: config.metrics_retention.ago
          )
        }
      end

      def post_cleanup(cleanup_counts)
        vacuum_database
        check_storage_warnings
        log_results(cleanup_counts)
        cleanup_counts.values.sum
      end

      def delete_telemetry_records(model, column:, cutoff:)
        return 0 unless data_source_available?(model)

        model.where("#{column} < ?", cutoff).delete_all
      end

      def record_snapshot_after_cleanup
        snapshots = StorageInfoSnapshot.call

        # StorageInfo.db_size_bytes is NOT NULL; record_snapshot coerces nil to 0.
        StorageInfo.record_snapshot(db_size: current_database_size, event_count: QueueEvent.count)

        snapshots.each do |snapshot|
          record_component_snapshot(snapshot)
        end
      end

      def record_component_snapshot(snapshot)
        return unless snapshot[:available]
        component = snapshot[:component]
        return if component == "queue_observer"

        StorageInfo.record_snapshot(
          component: component,
          db_size: snapshot[:db_size_bytes],
          event_count: snapshot[:event_count]
        )
      end

      def vacuum_database
        maintenance_statements.each do |statement|
          QueueEvent.connection.execute(statement)
        end
      rescue => error
        Rails.logger.warn "[SolidObserver] Database maintenance failed: #{error.message}"
      end

      def check_storage_warnings
        current_size = current_database_size
        return unless current_size
        return unless current_size > (SolidObserver.config.max_db_size * SolidObserver.config.warning_threshold)

        Rails.logger.warn(storage_warning_message(current_size))
      end

      def storage_warning_message(current_size)
        max_size = SolidObserver.config.max_db_size
        percentage = ((current_size.to_f / max_size) * 100).round(1)
        current_size_human = ActiveSupport::NumberHelper.number_to_human_size(
          current_size,
          precision: 1,
          significant: false,
          strip_insignificant_zeros: false
        )
        max_size_human = ActiveSupport::NumberHelper.number_to_human_size(
          max_size,
          precision: 1,
          significant: false,
          strip_insignificant_zeros: false
        )
        "[SolidObserver] Queue DB approaching limit: #{current_size_human} / #{max_size_human} (#{percentage}%)"
      end

      def current_database_size
        return @current_database_size if defined?(@current_database_size)

        @current_database_size = DatabaseSize.call(connection: QueueEvent.connection)
      end

      def log_results(cleanup_counts)
        Rails.logger.info(
          "[SolidObserver] Cleaned #{cleanup_counts[:queue_events]} queue events, " \
          "#{cleanup_counts[:cache_events]} cache events, " \
          "#{cleanup_counts[:cache_metrics]} cache metrics"
        )
      end

      def maintenance_statements
        tables = [QueueEvent, SolidObserver::CacheEvent, SolidObserver::CacheMetric].filter_map do |model|
          model.table_name if data_source_available?(model)
        end
        return [] if tables.empty?

        MAINTENANCE_STATEMENT_BUILDERS.fetch(QueueEvent.connection.adapter_name.downcase, ->(_known_tables) { [] }).call(tables)
      end

      def data_source_available?(model)
        table_name = model.table_name.to_s
        return false if table_name.empty?

        model.connection.data_source_exists?(table_name)
      rescue *StorageInfoSnapshot::CONNECTION_ERRORS, TypeError
        false
      end
    end
  end
end
