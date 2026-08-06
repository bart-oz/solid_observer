# frozen_string_literal: true

module SolidObserver
  class AlertRule < BaseRecord
    self.table_name = "solid_observer_alert_rules"

    METRIC_TYPES = %w[queue_latency error_rate storage_capacity health_score].freeze
    COMPARISON_OPERATORS = %w[> >= < <= ==].freeze

    validates :rule_name, presence: true, uniqueness: true, length: {maximum: 120}
    validates :metric_type, presence: true, inclusion: {in: METRIC_TYPES}
    validates :comparison_operator, presence: true, inclusion: {in: COMPARISON_OPERATORS}
    validates :threshold_value, presence: true, numericality: true
    validates :cooldown_minutes, numericality: {only_integer: true, greater_than_or_equal_to: 0}

    has_many :alert_histories,
      class_name: "SolidObserver::AlertHistory",
      foreign_key: :alert_rule_id,
      dependent: :delete_all

    scope :enabled, -> { where(enabled: true) }
  end
end
