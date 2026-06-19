# frozen_string_literal: true

module SolidObserver
  class CableMetric < BaseRecord
    self.table_name = "solid_observer_cable_metrics"

    validates :period_start, presence: true
    validates :broadcasts_count, :transmissions_count, :confirmations_count,
      :rejections_count, :perform_actions_count, :errors_count,
      numericality: {only_integer: true, greater_than_or_equal_to: 0}
  end
end
