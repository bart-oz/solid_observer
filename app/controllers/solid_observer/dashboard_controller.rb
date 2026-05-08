# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    def index
      assign_range_and_stats
      load_persistence_data if persistence_mode?
    end

    private

    def assign_range_and_stats
      range = QueueStats.parse_range(request_range_param)
      @range = range
      @stats = QueueStats.snapshot(range: range)
    end

    def load_persistence_data
      @recent_events = QueueEvent.recent(10)
      @recent_failures = QueueEvent.recent_failures(5)
    end

    def request_range_param
      request&.query_parameters&.[]("range") || request&.query_parameters&.[](:range)
    end
  end
end
