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
    CACHE_OUTCOME_STATES = {
      hit: {label: "Hit", tone: "success"},
      miss: {label: "Miss", tone: "info"},
      error: {label: "Error", tone: "danger"},
      recorded: {label: "Recorded", tone: "recorded"}
    }.freeze
    CACHE_RANGE_LABELS = {
      "15m" => "in last 15m",
      "30m" => "in last 30m",
      "1h" => "in last hour",
      "7h" => "in last 7h",
      "1d" => "in last day",
      "7d" => "in last 7d",
      "14d" => "in last 14d"
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

    def cache_ratio_percent(value)
      number_to_percentage(value.to_f * 100, precision: 1, strip_insignificant_zeros: true)
    end

    def cache_storage_summary(storage_components)
      snapshots = Array(storage_components)
      reason = cache_storage_unavailable_reason(snapshots)
      return {value: "—", subtitle: "— #{reason}"} if reason

      {
        value: number_to_human_size(cache_storage_total_bytes(snapshots), precision: 1, significant: false, strip_insignificant_zeros: false),
        subtitle: "SolidCache + cache observer"
      }
    end

    def cache_event_outcome_badge(event)
      meta = cache_event_outcome_meta(event)
      dot = tag.svg(
        tag.circle(r: 3, cx: 3, cy: 3, fill: "currentColor"),
        class: "so-badge__dot",
        viewBox: "0 0 6 6",
        "aria-hidden": "true"
      )

      tag.span(class: "so-badge so-badge--pill so-badge--#{meta[:tone]}") do
        safe_join([dot, meta[:label]], " ")
      end
    end

    def cache_event_digest(key_digest, visible_chars: 10)
      digest = key_digest.to_s
      return "—" if digest.empty?
      return digest if digest.length <= visible_chars

      "#{digest.first(visible_chars)}…"
    end

    def cache_range_label(range_key)
      CACHE_RANGE_LABELS.fetch(range_key.to_s, "in selected range")
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

    private

    def cache_storage_total_bytes(snapshots)
      snapshots.sum { |snapshot| snapshot[:db_size_bytes].to_i }
    end

    def cache_storage_unavailable_reason(snapshots)
      return "Storage snapshot unavailable" unless snapshots.size == 2

      snapshots.find { |snapshot| !snapshot[:available] }&.[](:unavailable_reason)
    end

    def cache_event_outcome_meta(event)
      hit = event.hit

      return CACHE_OUTCOME_STATES.fetch(:error) if event.error_class.present?
      return CACHE_OUTCOME_STATES.fetch(:hit) if hit == true
      return CACHE_OUTCOME_STATES.fetch(:miss) if hit == false

      CACHE_OUTCOME_STATES.fetch(:recorded)
    end
  end
end
