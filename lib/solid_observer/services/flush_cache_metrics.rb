# frozen_string_literal: true

module SolidObserver
  module Services
    class FlushCacheMetrics
      def self.call(metrics)
        new(metrics).call
      end

      def initialize(metrics)
        @metrics = metrics
      end

      def call
        return 0 if @metrics.empty?

        flush_metrics
        @metrics.size
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      private

      def flush_metrics
        SolidObserver::CacheMetric.transaction do
          @metrics.each { |metric_data| increment_metric(metric_data) }
        end
      end

      def increment_metric(metric_data)
        event_type, period_start = metric_data.values_at(:event_type, :period_start)
        metric = SolidObserver::CacheMetric.find_or_create_by!(
          event_type: event_type,
          period_start: period_start
        )

        SolidObserver::CacheMetric.where(id: metric.id).update_all(update_values(metric_data))
      end

      def update_values(metric_data)
        {
          operations_count: increment_expression(:operations_count, metric_data),
          hits_count: increment_expression(:hits_count, metric_data),
          misses_count: increment_expression(:misses_count, metric_data),
          errors_count: increment_expression(:errors_count, metric_data),
          duration_total: increment_expression(:duration_total, metric_data)
        }
      end

      def increment_expression(column, metric_data)
        value = quoted_value(metric_data.fetch(column, 0))
        Arel.sql("#{column} + #{value}")
      end

      def quoted_value(value)
        SolidObserver::CacheMetric.connection.quote(value)
      end
    end
  end
end
