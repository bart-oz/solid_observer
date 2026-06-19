# frozen_string_literal: true

module SolidObserver
  module Services
    class FlushCableMetrics
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
        SolidObserver::CableMetric.transaction do
          @metrics.each { |metric_data| increment_metric(metric_data) }
        end
      end

      def increment_metric(metric_data)
        period_start = metric_data.fetch(:period_start)
        metric = SolidObserver::CableMetric.find_or_create_by!(period_start: period_start)

        SolidObserver::CableMetric.where(id: metric.id).update_counters(update_values(metric_data))
      end

      def update_values(metric_data)
        {
          broadcasts_count: increment_expression(:broadcasts_count, metric_data),
          transmissions_count: increment_expression(:transmissions_count, metric_data),
          confirmations_count: increment_expression(:confirmations_count, metric_data),
          rejections_count: increment_expression(:rejections_count, metric_data),
          perform_actions_count: increment_expression(:perform_actions_count, metric_data),
          errors_count: increment_expression(:errors_count, metric_data)
        }
      end

      def increment_expression(column, metric_data)
        metric_data.fetch(column, 0)
      end
    end
  end
end
