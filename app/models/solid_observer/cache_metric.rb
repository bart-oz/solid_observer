# frozen_string_literal: true

module SolidObserver
  class CacheMetric < BaseMetric
    self.table_name = "solid_observer_cache_metrics"
    clear_validators!

    validates :event_type, presence: true, length: {maximum: 64}
    validates :period_start, presence: true
    validates :operations_count, :hits_count, :misses_count, :errors_count,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}
    validates :duration_total, numericality: {greater_than_or_equal_to: 0}
  end
end
