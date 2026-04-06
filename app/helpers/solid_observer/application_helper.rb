# frozen_string_literal: true

module SolidObserver
  module ApplicationHelper
    KB = 1_024
    MB = 1_048_576
    GB = 1_073_741_824

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

    def format_bytes(bytes)
      return "0 B" if bytes.to_i.zero?

      if bytes < KB
        "#{bytes.to_i} B"
      elsif bytes < MB
        "#{"%.1f" % (bytes / KB.to_f)} KB"
      elsif bytes < GB
        "#{"%.1f" % (bytes / MB.to_f)} MB"
      else
        "#{"%.1f" % (bytes / GB.to_f)} GB"
      end
    end

    def format_duration(seconds)
      return "0ms" if seconds.to_f.zero?

      if seconds < 1
        "#{(seconds * 1000).round}ms"
      else
        "#{"%.1f" % seconds}s"
      end
    end

    def format_number(number)
      number.to_i.to_s.reverse.gsub(/(\d{3})(?=\d)/, "\\1,").reverse
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
