# frozen_string_literal: true

module SolidObserver
  module CLI
    class Alerts < Base
      DEFAULT_LIMIT = 10
      CHANNEL_WIDTH = 10
      TIME_FORMAT = "%Y-%m-%d %H:%M"
      RULE_HEADERS = ["Rule", "Metric", "Threshold", "Cooldown", "State"].freeze
      INCIDENT_HEADERS = ["Rule", "State", "Severity", "Value", "Triggered", "Resolved"].freeze
      STATUS_COLORS = {success: :green, failed: :red}.freeze
      TEST_PAYLOAD = {
        "rule_name" => "solid_observer test alert",
        "severity" => "info",
        "metric_type" => "health_score",
        "threshold_value" => 0
      }.freeze
      SKIP_MESSAGE = "⚠️  Alerting is unavailable (realtime mode or alerts_enabled = false)"

      def list(limit: DEFAULT_LIMIT)
        return refuse(SKIP_MESSAGE) if skipped?

        print_header
        print_rules
        print_incidents("Active incidents", AlertHistory.active.order(triggered_at: :desc))
        print_incidents("Recent history", AlertHistory.recent(normalized_limit(limit)))
      end

      # Returns true when at least one channel accepted the preview, so the rake
      # wrapper can exit non-zero on a wholly failed smoke test.
      def test(channel: nil)
        return refuse(SKIP_MESSAGE) if skipped?
        return refuse("⚠️  Channel #{channel} is unknown or not configured") unless requested_channel_ok?(channel)

        report_results(Services::AlertNotification.call(
          alert_history: preview_history,
          event_type: "test",
          channels: channel.presence&.to_sym
        ))
      end

      private

      def skipped?
        config = SolidObserver.config
        config.realtime_mode? || !config.alerts_enabled
      end

      # An explicitly named channel bypasses AlertNotification's `configured`
      # predicate, so an unset webhook URL would surface as `TypeError` from
      # URI.parse(nil) and an unknown name as `KeyError`. Say what is actually
      # wrong instead.
      def requested_channel_ok?(channel)
        name = channel.presence&.to_sym
        return true unless name

        spec = Services::AlertNotification::CHANNELS[name]
        spec.present? && spec[:configured].call(SolidObserver.config)
      end

      # Every refusal path prints a warning and reports "nothing was delivered",
      # which the rake wrapper turns into exit 1.
      def refuse(message)
        warning(message)
        false
      end

      def print_header
        output("\n🔔 SolidObserver Alerts", color: :red)
        output("=" * 50, color: :red)
      end

      def normalized_limit(limit)
        value = limit.to_i
        value.positive? ? value : DEFAULT_LIMIT
      end

      # ponytail: no persisted rule or history row — a test alert must stay
      # invisible to AlertStatus.active_count, recent history, and cooldown.
      def preview_history
        AlertHistory.new(
          state: "triggered",
          metric_value: 0,
          triggered_at: Time.current,
          payload: TEST_PAYLOAD.merge("environment" => environment_name).to_json
        )
      end

      def environment_name
        defined?(Rails) ? Rails.env.to_s : "unknown"
      end

      def print_rules
        rules = AlertRule.order(:rule_name).to_a
        output("\nRules", color: :green)
        return warning("  No alert rules defined") if rules.empty?

        table(headers: RULE_HEADERS, rows: rules.map { |rule| rule_row(rule) })
      end

      def rule_row(rule)
        [
          rule.rule_name,
          rule.metric_type,
          "#{rule.comparison_operator} #{rule.threshold_value}",
          "#{rule.cooldown_minutes}m",
          rule.enabled? ? "enabled" : "disabled"
        ]
      end

      def print_incidents(title, scope)
        rows = scope.map { |history| incident_row(history) }
        output("\n#{title}", color: :green)
        return warning("  None") if rows.empty?

        table(headers: INCIDENT_HEADERS, rows: rows)
      end

      # Reads only AlertHistory#payload, which the model already slices to
      # SAFE_PAYLOAD_FIELDS — no raw metadata reaches the terminal.
      def incident_row(history)
        data = history.payload
        [
          data["rule_name"],
          history.state,
          data["severity"],
          history.metric_value,
          history.triggered_at&.strftime(TIME_FORMAT),
          history.resolved_at&.strftime(TIME_FORMAT) || "—"
        ]
      end

      # Prints one line per delivery attempt and reports whether anything got
      # through, which is what the rake wrapper turns into an exit code.
      def report_results(results)
        output("\n🔔 Test alert delivery", color: :red)
        return refuse("  No notification channels configured") if results.empty?

        results.each { |result| print_result(result) }
        results.any? { |result| result.status == :success }
      end

      # error_message is deliberately withheld: a channel exception can quote a
      # signed webhook URL. error_class is the safe required field (L0036).
      def print_result(result)
        status = result.status
        suffix = (status == :failed) ? "  (#{result.error_class})" : ""
        output("  #{result.channel.to_s.ljust(CHANNEL_WIDTH)}#{status}#{suffix}", color: STATUS_COLORS[status])
      end
    end
  end
end
