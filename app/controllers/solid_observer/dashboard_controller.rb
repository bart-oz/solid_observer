# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    def index
      @stats = QueueStats.snapshot

      if persistence_mode?
        @recent_events = QueueEvent.recent(10)
        @recent_failures = QueueEvent.recent_failures(5)
      end
    end
  end
end
