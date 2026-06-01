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
    DURATION_SEMANTICS = {
      "job_enqueued" => "Time spent in the ActiveJob enqueue call (Rails internal; typically sub-millisecond to single-digit ms)",
      "job_completed" => "Time spent performing the job",
      "job_failed" => "Time spent performing the job before the exception was raised",
      "job_discarded" => "Time before discard decision was made"
    }.freeze
    STABILITY_STATES = {
      stable: {label: "Stable", tone: "success"},
      degraded: {label: "Degraded", tone: "warning"},
      critical: {label: "Critical", tone: "danger"}
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

    def duration_with_semantic(value, event_type)
      return content_tag(:span, "—", class: "so-text-muted") unless value

      content_tag(:abbr, format_duration(value), title: DURATION_SEMANTICS.fetch(event_type.to_s))
    end

    def mode_badge
      config = SolidObserver.config
      color = config.persistence_mode? ? "info" : "warning"
      content_tag(:span, config.storage_mode.to_s.capitalize, class: "so-badge so-badge--#{color}")
    end

    def turbo_frame_tag(id, **options, &block)
      return super if defined?(super)

      content = options.delete(:content)
      body = block_given? ? capture(&block) : content

      content_tag(:"turbo-frame", body, **options.merge(id: id).compact)
    end

    def stability_state(stats)
      return :critical if stats[:failed_last_hour].to_i.positive?
      return :degraded if stats[:failed_last_24h].to_i.positive?

      :stable
    end

    def stability_badge(stats)
      meta = STABILITY_STATES.fetch(stability_state(stats))
      dot = tag.svg(tag.circle(r: 3, cx: 3, cy: 3),
        class: "so-badge__dot", viewBox: "0 0 6 6", "aria-hidden": "true")
      tag.span(class: "so-badge so-badge--pill so-badge--#{meta[:tone]}") do
        safe_join([dot, meta[:label]], " ")
      end
    end

    def stability_detail(stats)
      failures_24h = stats[:failed_last_24h].to_i
      return "No failures in the last 24h" if failures_24h.zero?

      "#{pluralize(failures_24h, "failure")} in the last 24h, latest #{latest_failure_phrase(stats[:latest_failure_at])}"
    end

    def latest_failure_phrase(timestamp)
      timestamp ? "#{time_ago_in_words(timestamp)} ago" : "unknown"
    end

    def queue_component_enabled?
      SolidObserver.config.solid_queue_enabled?
    end

    def cache_component_enabled?
      SolidObserver.config.solid_cache_enabled?
    end

    def dashboard_section_active?(component)
      current_component = @component.presence || "queue"
      controller_name == "dashboard" && current_component == component.to_s
    end
  end
end
