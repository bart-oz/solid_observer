# frozen_string_literal: true

require "active_support/lazy_load_hooks"

require_relative "solid_observer/version"
require_relative "solid_observer/configuration"
require_relative "solid_observer/correlation_id_resolver"
require_relative "solid_observer/correlated"
require_relative "solid_observer/params/jobs_filter"
require_relative "solid_observer/params/events_filter"
require_relative "solid_observer/services/ui_auth_check"
require_relative "solid_observer/subscriber"
require_relative "solid_observer/cli/base"
require_relative "solid_observer/cli/status"
require_relative "solid_observer/cli/storage"
require_relative "solid_observer/cli/jobs"
require_relative "solid_observer/cli/trace"
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
end

module SolidObserver
  autoload :ExecutionPresenter, File.expand_path("../app/presenters/solid_observer/execution_presenter", __dir__)

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
