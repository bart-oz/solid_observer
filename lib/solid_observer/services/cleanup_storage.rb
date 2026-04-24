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
    end
  end
end
