# frozen_string_literal: true

require_relative "health_score"
require_relative "database_size"

module SolidObserver
  module Services
    class EvaluateAlerts
      def self.call
        new.call
      end

      def initialize
        @triggered = 0
        @resolved = 0
        @metric_values = {}
      end

      def call
        return skip_summary if skip?

        AlertRule.enabled.find_each { |rule| evaluate_rule(rule) }
        {triggered: @triggered, resolved: @resolved, skipped: false}
      end

      private

      def skip?
        config = SolidObserver.config
        config.realtime_mode? || !config.alerts_enabled
      end

      def skip_summary
        reason = SolidObserver.config.realtime_mode? ? "realtime mode" : "alerts disabled"
        Rails.logger&.warn("[SolidObserver] EvaluateAlerts skipped: #{reason}")
        {triggered: 0, resolved: 0, skipped: true}
      end

      def evaluate_rule(rule)
        if breach?(rule)
          handle_breach(rule)
        else
          handle_recovery(rule)
        end
      end

      def breach?(rule)
        metric_value_for(rule.metric_type).public_send(rule.comparison_operator, rule.threshold_value)
      end

      def handle_breach(rule)
        return if cooldown_active?(rule) || rule.alert_histories.active.exists?

        trigger_alert(rule)
      end

      def cooldown_active?(rule)
        cooldown = rule.cooldown_minutes.to_i
        return false if cooldown.zero?

        last_resolved = rule.alert_histories.where(state: "resolved").maximum(:resolved_at)
        return false unless last_resolved

        last_resolved > cooldown.minutes.ago
      end

      def trigger_alert(rule)
        value = metric_value_for(rule.metric_type)
        history = AlertHistory.create!(
          alert_rule: rule,
          triggered_at: Time.current,
          metric_value: value,
          state: "triggered",
          payload: build_payload(rule, value)
        )
        SolidObserver::NotificationDeliveryJob.perform_later(history.id, "triggered")
        @triggered += 1
      end

      def handle_recovery(rule)
        active = rule.alert_histories.active.first
        return unless active

        active.resolve!
        SolidObserver::NotificationDeliveryJob.perform_later(active.id, "resolved")
        @resolved += 1
      end

      def build_payload(rule, value)
        metric_type = rule.metric_type
        {
          rule_name: rule.rule_name,
          metric_type: metric_type,
          metric_value: value,
          threshold_value: rule.threshold_value,
          triggered_at: Time.current,
          environment: environment,
          severity: severity_for(metric_type)
        }.to_json
      end

      def severity_for(metric_type)
        return "critical" if metric_type == "health_score" || health_snapshot[:overall] == :critical

        "warning"
      end

      def environment
        defined?(Rails) ? Rails.env.to_s : ""
      end

      def metric_value_for(metric_type)
        @metric_values[metric_type] ||= compute_metric_value(metric_type)
      end

      def compute_metric_value(metric_type)
        case metric_type
        when "queue_latency"
          queue_snapshot[:ready].to_i + queue_snapshot[:scheduled].to_i
        when "error_rate"
          compute_error_rate
        when "storage_capacity"
          database_size_bytes.to_i
        when "health_score"
          HealthScore::STATUS_RANK[health_snapshot[:overall]] || 0
        else
          0
        end
      end

      def compute_error_rate
        performed = queue_snapshot[:performed_in_range].to_f
        failed = queue_snapshot[:failed_in_range].to_f
        total = performed + failed
        total.positive? ? (failed / total) : 0.0
      end

      def queue_snapshot
        @queue_snapshot ||= SolidObserver::QueueStats.snapshot
      end

      def health_snapshot
        @health_snapshot ||= HealthScore.call
      end

      def database_size_bytes
        @database_size_bytes ||= DatabaseSize.call(connection: BaseRecord.connection)
      end
    end
  end
end
