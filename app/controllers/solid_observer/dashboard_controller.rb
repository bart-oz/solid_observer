# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    skip_forgery_protection only: :live_poll
    skip_after_action :verify_same_origin_request, only: :live_poll

    def index
      assign_range_and_stats
      load_persistence_data if persistence_mode?
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

      ChartBuffer.append(SolidQueue::ReadyExecution.count) if QueueStats.solid_queue_available?

      render json: {
        mode: persistence_mode? ? "persistence" : "realtime",
        snapshot: QueueStats.snapshot_for_poll(range: range),
        chart: QueueStats.chart_data(window: window)
      }
    end

    private

    def assign_range_and_stats
      range = QueueStats.parse_range(request_range_param)
      @range = range
      @live = request_live_param == "on"
      @stats = QueueStats.snapshot(range: range)
      @chart = QueueStats.chart_data(window: QueueStats.range_duration(@range))
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
  end
end
