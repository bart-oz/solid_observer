# frozen_string_literal: true

module SolidObserver
  module ApplicationHelper
    STATUS_COLORS = {
      "completed" => "success",
      "ready" => "success",
      "failed" => "danger",
      "retry_stopped" => "danger",
      "scheduled" => "warning",
      "claimed" => "warning",
      "enqueued" => "info",
      "discarded" => "info"
    }.freeze

    def execution_status(execution)
      ExecutionPresenter.new(execution).status
    end

    def format_duration(seconds)
      return "0ms" if seconds.to_f.zero?

      if seconds < 1
        "#{(seconds * 1000).round}ms"
      else
        "#{"%.1f" % seconds}s"
      end
    end

    def status_badge(status)
      status_str = status.to_s
      color = STATUS_COLORS.fetch(status_str, "default")
      content_tag(:span, status_str.humanize, class: "so-badge so-badge--#{color}")
    end

    def mode_badge
      config = SolidObserver.config
      color = config.persistence_mode? ? "info" : "warning"
      content_tag(:span, config.storage_mode.to_s.capitalize, class: "so-badge so-badge--#{color}")
    end
  end
end
