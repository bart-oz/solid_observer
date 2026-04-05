# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    def index
      @stats = QueueStats.snapshot

      if persistence_mode?
        @recent_events = QueueEvent
          .order(recorded_at: :desc)
          .limit(10)

        @recent_failures = QueueEvent
          .by_event_type("job_failed")
          .order(recorded_at: :desc)
          .limit(5)
      end
    end
  end
end
