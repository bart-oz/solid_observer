# frozen_string_literal: true

module SolidObserver
  module CLI
    class Storage < Base
      def call
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
          db_size_bytes: calculate_database_size,
          event_count: QueueEvent.count,
          max_size_bytes: SolidObserver.config.max_db_size
        }
      rescue => e
        {error: "Failed to gather storage stats: #{e.message}"}
      end

      def calculate_database_size
        db_config = QueueEvent.connection_db_config
        db_path = db_config.database

        return 0 unless File.exist?(db_path)

        File.size(db_path)
      rescue => e
        warning("Could not calculate database size: #{e.message}")
        0
      end

      def print_storage_table(stats)
        size_mb = bytes_to_mb(stats[:db_size_bytes])
        percentage = calculate_percentage(stats[:db_size_bytes], stats[:max_size_bytes])
        status = status_indicator(percentage)

        table(
          headers: ["Component", "Size", "Events", "Usage", "Status"],
          rows: [[
            "Queue",
            format_size(size_mb),
            format_number(stats[:event_count]),
            "#{percentage}%",
            status
          ]]
        )

        output("")
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
