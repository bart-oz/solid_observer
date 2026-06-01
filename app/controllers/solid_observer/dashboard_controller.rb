# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    skip_forgery_protection only: :live_poll
    skip_after_action :verify_same_origin_request, only: :live_poll

    def index
      @component = selected_component
      @queue_available_for_render = queue_dashboard_renderable?
      if @component == "queue" && @queue_available_for_render
        assign_range_and_stats
        load_persistence_data if persistence_mode?
      end
    end

    def live_poll
      send_file(
        SolidObserver::Engine.root.join("app/assets/javascripts/solid_observer/live_poll.js"),
        type: "application/javascript; charset=utf-8",
        disposition: "inline"
      )
    end

    def poll_data
      range = QueueStats.parse_range(request_range_param, fallback: QueueStats::POLL_DEFAULT_RANGE)
      window = QueueStats.range_duration(range, fallback: QueueStats::POLL_DEFAULT_RANGE)
      append_chart_buffer
      render json: tick_request? ? tick_payload : full_payload(range: range, window: window)
    end

    private

    def assign_range_and_stats
      range = QueueStats.parse_range(request_range_param)
      @range = range
      @live = request_live_param == "on"
      @stats = QueueStats.snapshot(range: range)
      @chart = if @stats[:available]
        QueueStats.chart_data(window: QueueStats.range_duration(@range))
      else
        {performed: [], failed: [], ready: []}
      end
    rescue
      @chart = {performed: [], failed: [], ready: []}
    end

    def load_persistence_data
      @recent_events = QueueEvent.recent(10)
    end

    def request_range_param
      request&.query_parameters&.[]("range") || request&.query_parameters&.[](:range)
    end

    def request_live_param
      request&.query_parameters&.[]("live") || request&.query_parameters&.[](:live)
    end

    def request_tick_param
      request&.query_parameters&.[]("tick") || request&.query_parameters&.[](:tick)
    end

    def tick_request?
      request_tick_param == "true"
    end

    def tick_payload
      {
        mode: persistence_mode? ? "persistence" : "realtime",
        snapshot: QueueStats.snapshot_for_tick,
        chart: nil
      }
    end

    def full_payload(range:, window:)
      {
        mode: persistence_mode? ? "persistence" : "realtime",
        snapshot: QueueStats.snapshot_for_poll(range: range),
        chart: QueueStats.chart_data(window: window),
        range_label: helpers.range_label(range)
      }
    end

    def append_chart_buffer
      ChartBuffer.append(SolidQueue::ReadyExecution.count) if QueueStats.solid_queue_available?
    end

    def selected_component
      requested = if request&.respond_to?(:path_parameters)
        request.path_parameters&.[](:component).to_s
      else
        ""
      end
      requested = path_component if requested.empty?
      return "cache" if requested == "cache" && SolidObserver.config.solid_cache_enabled?

      "queue"
    end

    def path_component
      return "" unless request&.respond_to?(:path)

      path = request&.path.to_s
      return "cache" if path.end_with?("/cache")
      return "queue" if path.end_with?("/queue")

      ""
    end

    def queue_dashboard_renderable?
      @component == "queue" && SolidObserver.config.solid_queue_enabled?
    end
  end
end
