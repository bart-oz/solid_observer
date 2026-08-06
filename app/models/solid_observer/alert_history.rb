# frozen_string_literal: true

module SolidObserver
  class AlertHistory < BaseRecord
    self.table_name = "solid_observer_alert_histories"

    STATES = %w[triggered resolved].freeze
    SAFE_PAYLOAD_FIELDS = %w[rule_name metric_type metric_value threshold_value triggered_at environment severity].freeze

    belongs_to :alert_rule, class_name: "SolidObserver::AlertRule", optional: false

    validates :triggered_at, presence: true
    validates :metric_value, presence: true, numericality: true
    validates :state, presence: true, inclusion: {in: STATES}

    scope :active, -> { where(state: "triggered") }
    scope :recent, ->(limit = 10) { order(triggered_at: :desc).limit(limit) }

    def resolve!(resolved_at: Time.current)
      update!(state: "resolved", resolved_at: resolved_at)
    end

    def payload
      (Hash.try_convert(JSON.parse(super || "{}")) || {}).slice(*SAFE_PAYLOAD_FIELDS)
    rescue JSON::ParserError
      {}
    end
  end
end
