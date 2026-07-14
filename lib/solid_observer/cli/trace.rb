# frozen_string_literal: true

module SolidObserver
  module CLI
    class Trace < Base
      DETAIL_FORMATTERS = {
        queue: :format_queue_details,
        cache: :format_cache_details,
        cable: :format_cable_details
      }.freeze

      EVENT_FORMATTERS = {
        "cable_summary" => ->(row) { "and #{row[:collapsed_count]} more cable events" }
      }.freeze

      def call(correlation_id:, limit: nil)
        return output("Trace unavailable in realtime mode.") if SolidObserver.config.realtime_mode?

        result = SolidObserver::Queries::TraceQuery.new.call(correlation_id: correlation_id, limit: limit)
        return warning("No events found for correlation_id: #{correlation_id}") if (rows = result.rows).empty?

        print_trace_table(rows)
        print_unavailable_components(result.unavailable_components)
      end

      private

      def print_trace_table(rows)
        print_section_header("Trace")
        table(
          headers: ["Time", "Component", "Event", "Details"],
          rows: rows.map { |row| format_cells(row) }
        )
        output("")
      end

      def print_unavailable_components(unavailable)
        unavailable.each { |component| warning("#{component} unavailable") }
      end

      def format_cells(row)
        recorded_at, component, event_type = row.values_at(:recorded_at, :component, :event_type)
        [
          format_time(recorded_at),
          component.to_s,
          event_type,
          format_details(row)
        ]
      end

      def format_details(row)
        event_type, component = row.values_at(:event_type, :component)
        event_formatter = EVENT_FORMATTERS[event_type]
        return event_formatter.call(row) if event_formatter

        component_formatter = DETAIL_FORMATTERS[component]
        send(component_formatter, row) if component_formatter
      end

      def format_queue_details(row)
        job_class, queue_name, duration = row.values_at(:job_class, :queue_name, :duration)
        [label("job", job_class), label("queue", queue_name), duration_part(duration)].compact.join(" ")
      end

      def format_cache_details(row)
        hit, error_class, duration = row.values_at(:hit, :error_class, :duration)
        [hit_part(hit), error_part(error_class), duration_part(duration)].compact.join(" ")
      end

      def format_cable_details(row)
        channel_class, duration, error_class, collapsed_count = row.values_at(:channel_class, :duration, :error_class, :collapsed_count)
        [label("channel", channel_class), error_part(error_class), duration_part(duration), ("collapsed=#{collapsed_count}" if collapsed_count)].compact.join(" ")
      end

      def label(name, value)
        "#{name}=#{value}" if value
      end

      def error_part(error_class)
        "error=#{error_class}" if error_class
      end

      def hit_part(hit)
        "hit=#{hit}" if [true, false].include?(hit)
      end

      def duration_part(duration)
        "duration=#{format_duration(duration)}" if duration
      end

      def format_duration(duration)
        duration ? "#{duration.round(3)}s" : nil
      end

      def format_time(time)
        time.strftime("%Y-%m-%d %H:%M:%S")
      end

      def print_section_header(title)
        output("\n#{title}", color: :red)
        output("=" * 50, color: :red)
        output("")
      end
    end
  end
end
