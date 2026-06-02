# frozen_string_literal: true

module SolidObserver
  module CLI
    class Storage < Base
      def call
        print_section_header("💾 Storage Status")
        return print_realtime_mode_message if SolidObserver.config.realtime_mode?

        render_storage_status
      end

      private

      def print_realtime_mode_message
        info("Storage monitoring is not available in real-time mode.")
        info("Switch to persistence mode for event history and storage tracking.")
        output("")
      end

      def render_storage_status
        current_stats = gather_storage_stats
        error_message = current_stats[:error]
        return error(error_message) if error_message

        print_storage_table(current_stats)
        print_configuration
      end

      def gather_storage_stats
        {components: SolidObserver::Services::StorageInfoSnapshot.call, max_size_bytes: SolidObserver.config.max_db_size}
      rescue => e
        {error: "Failed to gather storage stats: #{e.message}"}
      end

      def print_storage_table(stats)
        max_size_bytes = stats[:max_size_bytes]
        components = stats[:components]

        table(
          headers: ["Component", "Size", "Events", "Usage", "Status"],
          rows: components.map { |component| storage_row(component: component, max_size_bytes: max_size_bytes) }
        )

        output("")
      end

      def storage_row(component:, max_size_bytes:)
        event_count = component[:event_count]
        size, usage, status = storage_displays(component: component, max_size_bytes: max_size_bytes)

        [
          component[:label],
          size,
          event_count ? format_number(event_count) : "—",
          usage,
          status
        ]
      end

      def storage_displays(component:, max_size_bytes:)
        return unavailable_displays unless component[:available]

        db_size_bytes = component[:db_size_bytes]
        return ["N/A", "N/A", "— Unknown"] unless db_size_bytes

        percentage = calculate_percentage(db_size_bytes, max_size_bytes)
        [format_size(bytes_to_mb(db_size_bytes)), "#{percentage}%", status_indicator(percentage)]
      end

      def unavailable_displays
        ["—", "—", "— Unavailable"]
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
        output(title, color: :red)
        output("=" * 50, color: :red)
        output("")
      end
    end
  end
end
