# frozen_string_literal: true

module SolidObserver
  module Queries
    class TraceQuery
      DEFAULT_LIMIT = 100
      CABLE_CAP = 50

      Result = Struct.new(:rows, :unavailable_components, keyword_init: true)

      COMPONENT_PRIORITY = {queue: 0, cache: 1, cable: 2}.freeze

      COMPONENT_CONFIG = {
        queue: {
          enabled: :solid_queue_enabled?,
          model: :QueueEvent,
          columns: [:recorded_at, :event_type, :job_class, :queue_name, :duration, :id]
        },
        cache: {
          enabled: :solid_cache_enabled?,
          model: :CacheEvent,
          columns: [:recorded_at, :event_type, :hit, :error_class, :duration, :id]
        },
        cable: {
          enabled: :solid_cable_enabled?,
          model: :CableEvent,
          columns: [:recorded_at, :event_type, :channel_class, :broadcasting_digest, :error_class, :duration, :id]
        }
      }.freeze

      CONNECTION_ERRORS = [
        ActiveRecord::ConnectionNotEstablished,
        ActiveRecord::StatementInvalid,
        *([PG::ConnectionBad] if defined?(PG::ConnectionBad)),
        *([Mysql2::Error::ConnectionError] if defined?(Mysql2::Error::ConnectionError)),
        *([Trilogy::Error] if defined?(Trilogy::Error)),
        *([SQLite3::CantOpenException] if defined?(SQLite3::CantOpenException))
      ].freeze

      def call(correlation_id:, limit: DEFAULT_LIMIT)
        rows, unavailable = gather_rows(correlation_id)
        effective_limit = limit.to_i
        effective_limit = DEFAULT_LIMIT unless effective_limit.positive?
        Result.new(rows: process_rows(rows, effective_limit), unavailable_components: unavailable)
      end

      private

      def gather_rows(correlation_id)
        COMPONENT_CONFIG.each_with_object([[], []]) do |(component, config), (rows, unavailable)|
          next unless SolidObserver.config.public_send(config[:enabled])

          component_rows = fetch_component_rows(component, config, correlation_id)
          component_rows ? rows.concat(component_rows) : unavailable << component
        end
      end

      def fetch_component_rows(component, config, correlation_id)
        model = SolidObserver.const_get(config[:model])
        return nil unless data_source_available?(model)

        pluck_rows(model, component, correlation_id)
      rescue *CONNECTION_ERRORS, TypeError
        nil
      end

      def data_source_available?(model)
        table_name = model.table_name.to_s
        table_name.present? && model.connection.data_source_exists?(table_name)
      end

      def pluck_rows(model, component, correlation_id)
        columns = COMPONENT_CONFIG[component][:columns]
        model.where(correlation_id: correlation_id)
          .order(:recorded_at)
          .pluck(*columns)
          .map { |values| build_row(component, columns, values) }
      end

      def build_row(component, columns, values)
        row = {component: component}
        columns.each_with_index { |column, index| row[column] = values[index] }
        row
      end

      def process_rows(rows, limit)
        collapsed = collapse_cable_rows(rows)
        capped = apply_cable_cap(collapsed)
        sorted = sort_rows(capped)
        return sorted if capped.size <= limit

        sort_rows(sorted.last(limit))
      end

      def collapse_cable_rows(rows)
        cable_rows, other_rows = rows.partition { |row| row[:component] == :cable }
        return rows if cable_rows.empty?

        other_rows + cable_rows.chunk_while(&method(:collapse_match?)).map(&method(:collapse_group))
      end

      def collapse_match?(first_row, second_row)
        return false unless first_row[:event_type] == "broadcast" && second_row[:event_type] == "broadcast"

        digest = first_row[:broadcasting_digest]
        digest.present? && digest == second_row[:broadcasting_digest]
      end

      def collapse_group(group)
        row = group.first
        size = group.size
        row[:collapsed_count] = size if size > 1
        row.delete(:broadcasting_digest)
        row
      end

      def apply_cable_cap(rows)
        cable_rows, other_rows = rows.partition { |row| row[:component] == :cable }
        total = cable_rows.size
        return rows if total <= CABLE_CAP

        other_rows + cap_cable_rows(cable_rows, total)
      end

      def cap_cable_rows(cable_rows, total)
        keep_count = CABLE_CAP - 1
        [build_summary_row(cable_rows.first(total - keep_count))] + tail_rows(cable_rows, keep_count)
      end

      def tail_rows(rows, count)
        rows.last(count)
      end

      def build_summary_row(overflow)
        {
          recorded_at: overflow.last[:recorded_at],
          component: :cable,
          event_type: "cable_summary",
          duration: nil,
          channel_class: nil,
          collapsed_count: overflow.size,
          id: -1
        }
      end

      def sort_rows(rows)
        rows.sort_by { |row| [row[:recorded_at], COMPONENT_PRIORITY[row[:component]], row[:id] || 0] }
      end
    end
  end
end
