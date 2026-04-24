# frozen_string_literal: true

module SolidObserver
  module RequireSolidQueue
    extend ActiveSupport::Concern

    included do
      before_action :require_solid_queue
    end

    private

    def require_solid_queue
      return if SolidObserver::QueueStats.solid_queue_available?

      redirect_to root_path, alert: "SolidQueue is not available."
    end
  end
end
