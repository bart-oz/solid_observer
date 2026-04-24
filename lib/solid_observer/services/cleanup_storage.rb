# frozen_string_literal: true

require_relative "database_size"

module SolidObserver
  module Services
    class CleanupStorage
      def self.call
        new.call
      end

      def call
        return 0 if SolidObserver.config.realtime_mode?

        deleted_count = 0

        QueueEvent.transaction do
          deleted_count = delete_old_events
          record_snapshot_after_cleanup
        end

        vacuum_database

        check_storage_warnings
        log_results(deleted_count)

        deleted_count
      rescue => e
        Rails.logger.error "[SolidObserver] Cleanup failed: #{e.message}"
        raise
      end

      private

      def delete_old_events
        cutoff = SolidObserver.config.event_retention.ago
        QueueEvent.where("recorded_at < ?", cutoff).delete_all
      end

      def record_snapshot_after_cleanup
        # StorageInfo.db_size_bytes is NOT NULL; record_snapshot coerces nil to 0.
        StorageInfo.record_snapshot(
          db_size: current_database_size,
          event_count: QueueEvent.count
        )
      end

      def vacuum_database
        adapter = QueueEvent.connection.adapter_name.downcase
        case adapter
        when "sqlite"
          QueueEvent.connection.execute("VACUUM")
        when "postgresql"
          QueueEvent.connection.execute("VACUUM ANALYZE solid_observer_queue_events")
        when "mysql2", "trilogy"
          QueueEvent.connection.execute("OPTIMIZE TABLE solid_observer_queue_events")
        end
      rescue => e
        Rails.logger.warn "[SolidObserver] Database maintenance failed: #{e.message}"
      end

      def check_storage_warnings
        current_size = current_database_size
        return unless current_size

        max_size = SolidObserver.config.max_db_size
        threshold = SolidObserver.config.warning_threshold

        return unless current_size > (max_size * threshold)

        percentage = ((current_size.to_f / max_size) * 100).round(1)
        Rails.logger.warn "[SolidObserver] Queue DB approaching limit: #{format_bytes(current_size)} / #{format_bytes(max_size)} (#{percentage}%)"
      end

      def current_database_size
        return @current_database_size if defined?(@current_database_size)

        @current_database_size = DatabaseSize.call(connection: QueueEvent.connection)
      end

      def log_results(deleted_count)
        Rails.logger.info "[SolidObserver] Cleaned #{deleted_count} queue events"
      end

      def format_bytes(bytes)
        return "0 B" if bytes.zero?

        units = ["B", "KB", "MB", "GB"]
        exp = (Math.log(bytes) / Math.log(1024)).to_i
        exp = [exp, units.length - 1].min

        "%.1f %s" % [bytes.to_f / (1024**exp), units[exp]]
      end
    end
  end
end
