# frozen_string_literal: true

require_relative "database_size"
require_relative "storage_info_snapshot"

module SolidObserver
  module Services
    class CleanupStorage
      def self.call
        new.call
      end

      def call
        return 0 if SolidObserver.config.realtime_mode?

        deleted_count = perform_cleanup_transaction
        post_cleanup(deleted_count)
      rescue => e
        handle_cleanup_failure(e)
      end

      private

      def handle_cleanup_failure(error)
        Rails.logger.error "[SolidObserver] Cleanup failed: #{error.message}"
        raise
      end

      def perform_cleanup_transaction
        QueueEvent.transaction do
          deleted_count = delete_old_events
          record_snapshot_after_cleanup
          deleted_count
        end
      end

      def post_cleanup(deleted_count)
        vacuum_database
        check_storage_warnings
        log_results(deleted_count)
        deleted_count
      end

      def delete_old_events
        cutoff = SolidObserver.config.event_retention.ago
        QueueEvent.where("recorded_at < ?", cutoff).delete_all
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
        statement = maintenance_statement
        return unless statement

        QueueEvent.connection.execute(statement)
      rescue => e
        Rails.logger.warn "[SolidObserver] Database maintenance failed: #{e.message}"
      end

      def check_storage_warnings
        current_size = current_database_size
        return unless warning_needed?(current_size)

        Rails.logger.warn(storage_warning_message(current_size))
      end

      def warning_needed?(current_size)
        return false unless current_size

        config = SolidObserver.config
        max_size = config.max_db_size
        threshold = config.warning_threshold
        current_size > (max_size * threshold)
      end

      def storage_warning_message(current_size)
        max_size = SolidObserver.config.max_db_size
        percentage = ((current_size.to_f / max_size) * 100).round(1)
        current_size_human = human_size(current_size)
        max_size_human = human_size(max_size)
        "[SolidObserver] Queue DB approaching limit: #{current_size_human} / #{max_size_human} (#{percentage}%)"
      end

      def human_size(bytes)
        ActiveSupport::NumberHelper.number_to_human_size(bytes, precision: 1, significant: false, strip_insignificant_zeros: false)
      end

      def current_database_size
        return @current_database_size if defined?(@current_database_size)

        @current_database_size = DatabaseSize.call(connection: QueueEvent.connection)
      end

      def log_results(deleted_count)
        Rails.logger.info "[SolidObserver] Cleaned #{deleted_count} queue events"
      end

      def maintenance_statement
        case QueueEvent.connection.adapter_name.downcase
        when "sqlite" then "VACUUM"
        when "postgresql" then "VACUUM ANALYZE solid_observer_queue_events"
        when "mysql2", "trilogy" then "OPTIMIZE TABLE solid_observer_queue_events"
        end
      end
    end
  end
end
