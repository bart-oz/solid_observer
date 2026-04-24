# frozen_string_literal: true

module SolidObserver
  module RequirePersistenceMode
    extend ActiveSupport::Concern

    included do
      before_action :require_persistence_mode
    end

    private

    def require_persistence_mode
      return unless SolidObserver.config.realtime_mode?

      redirect_to root_path, alert: "This page is not available in real-time mode."
    end
  end
end
