# frozen_string_literal: true

module SolidObserver
  class EventsController < ApplicationController
    include Paginatable
    include RequirePersistenceMode

    PER_PAGE = 50

    def index
      filter = Params::EventsFilter.from_params(params)
      @event_type = filter.event_type
      @job_class = filter.job_class
      @queue_name = filter.queue_name
      @from = filter.from
      @to = filter.to
      @page = filter.page
      scope = Queries::EventsQuery.new(filter).call
      offset = paginate_scope(scope, per_page: PER_PAGE)
      @events = scope.limit(PER_PAGE).offset(offset)
      load_available_options
    end

    def show
      @event = QueueEvent.find_by(id: params[:id])
      return redirect_to(events_path, alert: "Event not found") unless @event

      @metadata = parse_metadata(@event.metadata)
    end

    private

    def load_available_options
      @available_event_types = QueueEvent::EVENT_TYPES
      @available_job_classes = cached_filter_options("solid_observer/events/distinct_job_classes") { QueueEvent.distinct_job_classes }
      @available_queues = cached_filter_options("solid_observer/events/distinct_queue_names") { QueueEvent.distinct_queue_names }
    end

    def cached_filter_options(key, &block)
      Rails.cache.fetch(key, expires_in: SolidObserver.config.filter_cache_ttl, &block)
    end

    def parse_metadata(metadata)
      return nil if metadata.blank?
      JSON.parse(metadata)
    rescue JSON::ParserError
      {raw: metadata}
    end
  end
end
