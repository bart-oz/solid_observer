# frozen_string_literal: true

module SolidObserver
  module Services
    class AlertStatus
      def self.active_count
        new.active_count
      end

      def active_count
        config = SolidObserver.config
        return 0 if config.realtime_mode? || !config.alerts_enabled

        AlertHistory.active.count
      end
    end
  end
end
