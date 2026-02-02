# frozen_string_literal: true

module SolidObserver
  # BaseMetric provides the foundation for time-series metrics storage.
  #
  # NOTE: Metrics functionality is planned for v0.2.0. The database connection
  # will be configured by the Engine (similar to BaseEvent) when metrics are
  # fully implemented.
  #
  class BaseMetric < ActiveRecord::Base
    self.abstract_class = true
    self.table_name = "solid_observer_metrics"

    PERIOD_TYPES = %w[minute hour day].freeze

    validates :metric_name, presence: true
    validates :value, presence: true, numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :period_start, presence: true
    validates :period_type, presence: true, inclusion: {in: PERIOD_TYPES}

    scope :for_metric, ->(name) { where(metric_name: name) }
    scope :hourly, -> { where(period_type: "hour") }
    scope :daily, -> { where(period_type: "day") }
    scope :minutely, -> { where(period_type: "minute") }
    scope :since, ->(time) { where("period_start >= ?", time) }
    scope :between, ->(start_time, end_time) { where(period_start: start_time..end_time) }

    class << self
      def increment(metric:, period: Time.current.beginning_of_hour, period_type: "hour", by: 1)
        record = find_or_create_by!(
          metric_name: metric,
          period_start: period,
          period_type: period_type
        )
        record.increment!(:value, by)
        record
      rescue ActiveRecord::RecordNotUnique
        retry
      end

      def record(metric:, value:, period: Time.current.beginning_of_hour, period_type: "hour")
        upsert(
          {
            metric_name: metric,
            value: value,
            period_start: period,
            period_type: period_type
          },
          unique_by: [:metric_name, :period_start, :period_type]
        )
        find_by!(
          metric_name: metric,
          period_start: period,
          period_type: period_type
        )
      end
    end
  end
end
