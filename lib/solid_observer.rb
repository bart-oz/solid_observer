# frozen_string_literal: true

require "active_support/lazy_load_hooks"
require "action_mailer/railtie"

require_relative "solid_observer/version"
require_relative "solid_observer/configuration"
require_relative "solid_observer/correlation_id_resolver"
require_relative "solid_observer/correlated"
require_relative "solid_observer/params/jobs_filter"
require_relative "solid_observer/params/events_filter"
require_relative "solid_observer/services/ui_auth_check"
require_relative "solid_observer/channels/base"
require_relative "solid_observer/channels/slack"
require_relative "solid_observer/channels/email"
require_relative "solid_observer/channels/webhook"
require_relative "solid_observer/services/alert_payload"
require_relative "solid_observer/services/alert_notification"
require_relative "solid_observer/subscriber"
require_relative "solid_observer/cli/base"
require_relative "solid_observer/cli/status"
require_relative "solid_observer/cli/storage"
require_relative "solid_observer/cli/jobs"
require_relative "solid_observer/cli/trace"
require_relative "solid_observer/cli/health"
require_relative "solid_observer/cli/alerts"
require_relative "solid_observer/queue_stats"
require_relative "solid_observer/engine" if defined?(Rails::Engine)

ActiveSupport.on_load(:active_record) do
  require_relative "solid_observer/base_record"
  require_relative "solid_observer/base_event"
  require_relative "solid_observer/base_metric"
  require_relative "solid_observer/queries/job_executions_query"
  require_relative "solid_observer/queries/events_query"
  require_relative "solid_observer/queries/trace_query"
  require_relative "solid_observer/queries/execution_finder"
  require_relative "solid_observer/services/record_event"
  require_relative "solid_observer/services/flush_event_buffer"
  require_relative "solid_observer/services/cleanup_storage"
  require_relative "solid_observer/queue_event_buffer"
  require_relative "solid_observer/cache_event_buffer"
  require_relative "solid_observer/services/flush_cache_metrics"
  require_relative "solid_observer/cache_metric_buffer"
  require_relative "solid_observer/cache_subscriber"
  require_relative "solid_observer/services/record_cache_event"
  require_relative "solid_observer/services/record_cache_metric"
  require_relative "solid_observer/services/flush_cache_event_buffer"
  require_relative "solid_observer/services/cache_stats"
  require_relative "solid_observer/services/cache_operations"
  require_relative "solid_observer/cable_event_buffer"
  require_relative "solid_observer/services/flush_cable_metrics"
  require_relative "solid_observer/cable_metric_buffer"
  require_relative "solid_observer/cable_subscriber"
  require_relative "solid_observer/services/record_cable_event"
  require_relative "solid_observer/services/record_cable_metric"
  require_relative "solid_observer/services/flush_cable_event_buffer"
  require_relative "solid_observer/services/cable_stats"
  require_relative "solid_observer/services/cable_operations"
  require_relative "solid_observer/services/health_score"
  require_relative "solid_observer/services/unified_feed"
  require_relative "solid_observer/services/database_size"
  require_relative "solid_observer/services/evaluate_alerts"
  require_relative "solid_observer/services/alert_status"
end
module SolidObserver
  autoload :ExecutionPresenter, File.expand_path("../app/presenters/solid_observer/execution_presenter", __dir__)
  autoload :AlertMailer, File.expand_path("../app/mailers/solid_observer/alert_mailer", __dir__)

  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def config
      configuration
    end

    def reset_configuration!
      @configuration = Configuration.new
    end
  end
end
