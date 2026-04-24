# frozen_string_literal: true

module SolidObserver
  module CLI
    class Storage < Base
      def call
        if SolidObserver.config.realtime_mode?
          print_section_header("💾 Storage Status")
          info("Storage monitoring is not available in real-time mode.")
          info("Switch to persistence mode for event history and storage tracking.")
          output("")
          return
        end

        print_section_header("💾 Storage Status")

        current_stats = gather_storage_stats

        if current_stats[:error]
          error(current_stats[:error])
          return
        end

        print_storage_table(current_stats)
        print_configuration
      end

      private

      def gather_storage_stats
        {
          db_size_bytes: SolidObserver::Services::DatabaseSize.call(connection: QueueEvent.connection),
          event_count: QueueEvent.count,
          max_size_bytes: SolidObserver.config.max_db_size
        }
      rescue => e
        {error: "Failed to gather storage stats: #{e.message}"}
      end

      def print_storage_table(stats)
        event_count = stats[:event_count]
        db_size_bytes = stats[:db_size_bytes]
        max_size_bytes = stats[:max_size_bytes]

        table(
          headers: ["Component", "Size", "Events", "Usage", "Status"],
          rows: [storage_row(event_count: event_count, db_size_bytes: db_size_bytes, max_size_bytes: max_size_bytes)]
        )

        output("")
      end

      def storage_row(event_count:, db_size_bytes:, max_size_bytes:)
        size, usage, status = storage_displays(db_size_bytes, max_size_bytes)

        [
          "Queue",
          size,
          format_number(event_count),
          usage,
          status
        ]
      end

      def storage_displays(db_size_bytes, max_size_bytes)
        return ["N/A", "N/A", "— Unknown"] unless db_size_bytes

        percentage = calculate_percentage(db_size_bytes, max_size_bytes)
        [format_size(bytes_to_mb(db_size_bytes)), "#{percentage}%", status_indicator(percentage)]
      end

      def print_configuration
        retention_days = (SolidObserver.config.event_retention / 1.day).to_i
        max_size_mb = bytes_to_mb(SolidObserver.config.max_db_size)

        info("Configuration:")
        output("  Retention: #{retention_days} days")
        output("  Max size:  #{format_size(max_size_mb)} per database")
        output("  Warning:   #{(SolidObserver.config.warning_threshold * 100).to_i}% threshold")
        output("")
      end

      def bytes_to_mb(bytes)
        (bytes / 1_048_576.0).round(2)
      end

      def calculate_percentage(current, max)
        return 0.0 if max.zero?

        ((current.to_f / max) * 100).round(2)
      end

      def status_indicator(percentage)
        threshold = SolidObserver.config.warning_threshold * 100

        if percentage >= threshold
          "⚠️  Warning"
        else
          "✓ OK"
        end
      end

      def format_size(size_mb)
        if size_mb >= 1024
          "#{(size_mb / 1024.0).round(2)} GB"
        else
          "#{size_mb} MB"
        end
      end

      def format_number(number)
        number.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\\1,').reverse
      end

      def print_section_header(title)
        output("")
        output(title, color: :cyan)
        output("=" * 50, color: :cyan)
        output("")
      end
    end
  end
end
