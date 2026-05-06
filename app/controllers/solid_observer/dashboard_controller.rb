# frozen_string_literal: true

module SolidObserver
  class DashboardController < ApplicationController
    def index
      @stats = QueueStats.snapshot

      @recent_events = QueueEvent.recent(10) if persistence_mode?
    end
  end
end
