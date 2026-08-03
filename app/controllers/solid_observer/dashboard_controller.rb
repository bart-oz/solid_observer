# frozen_string_literal: true

require_relative "../../helpers/solid_observer/application_helper"

module SolidObserver
  class DashboardController < ApplicationController
    helper SolidObserver::ApplicationHelper

    skip_forgery_protection only: :live_poll
    skip_after_action :verify_same_origin_request, only: :live_poll

    def index
      @component = selected_component

      if @component == "queue" && SolidObserver.config.solid_queue_enabled?
        assign_range_and_stats
        load_persistence_data if persistence_mode?
      elsif @component == "home"
        @health = begin
          Services::HealthScore.call
        rescue => error
          Rails.logger&.warn("Home HealthScore: #{error.class}: #{error.message}")
          {overall: :degraded, components: {}}
        end
        @feed = begin
          Services::UnifiedFeed.call
        rescue => error
          Rails.logger&.warn("Home UnifiedFeed: #{error.class}: #{error.message}")
          []
        end
      end
    end

    def live_poll
      expires_in 1.day, public: true
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
      return "queue" if requested == "queue" && SolidObserver.config.solid_queue_enabled?
      return "cache" if requested == "cache" && SolidObserver.config.solid_cache_enabled?

      "home"
    end

    def path_component
      return "" unless request&.respond_to?(:path)

      path = request&.path.to_s
      return "queue" if path.end_with?("/queue")
      return "cache" if path.end_with?("/cache")

      ""
    end
  end
end
