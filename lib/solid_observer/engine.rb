# frozen_string_literal: true

module SolidObserver
  class Engine < ::Rails::Engine
    isolate_namespace SolidObserver

    class << self
      def check_solid_queue_availability
        return if defined?(SolidQueue)

        Rails.logger.warn "[SolidObserver] SolidQueue not detected. Queue observability features will be limited."
      end

      def check_and_activate_subscribers
        logger = Rails.logger

        if ActiveRecord::Base.connection.table_exists?("solid_observer_queue_events")
          logger.info "[SolidObserver] Tables detected, activating event subscribers"
          # TODO: Activate event subscribers in SO-010
        else
          logger.info "[SolidObserver] Tables not found. Run migrations: rails solid_observer:install:migrations && rails db:migrate"
        end
      rescue ActiveRecord::NoDatabaseError
        logger.info "[SolidObserver] Database not ready yet. Skipping subscriber activation."
      end
    end

    config.before_initialize do
      Engine.check_solid_queue_availability
    end

    initializer "solid_observer.check_tables" do
      ActiveSupport.on_load(:active_record) do
        config.after_initialize do
          Engine.check_and_activate_subscribers
        end
      end
    end
  end
end
