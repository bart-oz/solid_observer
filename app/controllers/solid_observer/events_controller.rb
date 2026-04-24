# frozen_string_literal: true

module SolidObserver
  class EventsController < ApplicationController
    before_action :require_persistence_mode
    before_action :set_event, only: [:show]

    PER_PAGE = 50

    def index
      set_filter_params
      scope = build_event_scope
      paginate_events(scope)
      load_available_options
    end

    def show
      @metadata = parse_metadata(@event.metadata)
    end

    private

    def set_filter_params
      @event_type = params[:event_type].presence
      @job_class = params[:job_class].presence
      @queue_name = params[:queue_name].presence
      @from = parse_date(params[:from])
      @to = parse_date(params[:to])
      @page = (params[:page].presence || 1).to_i
    end

    def build_event_scope
      scope = SolidObserver::QueueEvent.order(recorded_at: :desc)
      scope = scope.by_event_type(@event_type) if @event_type.present?
      scope = scope.by_job_class(@job_class) if @job_class.present?
      scope = scope.by_queue(@queue_name) if @queue_name.present?
      scope = scope.since(@from.beginning_of_day) if @from
      scope = scope.before(@to.end_of_day) if @to
      scope
    end

    def paginate_events(scope)
      offset = paginate_scope(scope, per_page: PER_PAGE)
      @events = scope.limit(PER_PAGE).offset(offset)
    end

    def load_available_options
      @available_event_types = SolidObserver::QueueEvent::EVENT_TYPES
      @available_job_classes = cached_filter_options("solid_observer/events/distinct_job_classes") {
        SolidObserver::QueueEvent.distinct_job_classes
      }
      @available_queues = cached_filter_options("solid_observer/events/distinct_queue_names") {
        SolidObserver::QueueEvent.distinct_queue_names
      }
    end

    def cached_filter_options(key, &block)
      Rails.cache.fetch(key, expires_in: SolidObserver.config.filter_cache_ttl, &block)
    end

    def set_event
      @event = SolidObserver::QueueEvent.find_by(id: params[:id])
      redirect_to(events_path, alert: "Event not found") and return unless @event
    end

    def parse_date(date_string)
      return nil if date_string.blank?

      Date.parse(date_string)
    rescue ArgumentError
      nil
    end

    def parse_metadata(metadata)
      return nil if metadata.blank?

      JSON.parse(metadata)
    rescue JSON::ParserError
      {raw: metadata}
    end
  end
end
