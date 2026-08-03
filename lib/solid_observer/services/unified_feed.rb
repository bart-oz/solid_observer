# frozen_string_literal: true

module SolidObserver
  module Services
    class UnifiedFeed
      SAFE_KEYS = %i[component event_type recorded_at detail correlation_id error_class].freeze

      def self.call(limit: 20)
        new(limit: limit).call
      end

      def initialize(limit:)
        @limit = limit
        @config = SolidObserver.config
      end

      def call
        return [] if @config.realtime_mode?

        rows = []
        rows.concat(queue_rows) if @config.solid_queue_enabled?
        rows.concat(cache_rows) if @config.solid_cache_enabled?
        rows.concat(cable_rows) if @config.solid_cable_enabled?

        rows.sort_by { |row| row[:recorded_at] || Time.at(0) }.reverse.first(@limit)
      end

      private

      def queue_rows
        QueueEvent.recent(@limit).map { |e| normalize_queue(e) }
      rescue => error
        log_error(:queue, error)
        []
      end

      def cache_rows
        CacheEvent.recent(@limit).map { |e| normalize_cache(e) }
      rescue => error
        log_error(:cache, error)
        []
      end

      def cable_rows
        CableEvent.recent(@limit).map { |e| normalize_cable(e) }
      rescue => error
        log_error(:cable, error)
        []
      end

      def normalize_queue(event)
        {
          component: :queue,
          event_type: event.event_type,
          recorded_at: event.recorded_at,
          detail: [event.job_class, event.queue_name].compact.join(" · "),
          correlation_id: event.correlation_id,
          error_class: nil # queue events have no error_class column
        }
      end

      def normalize_cache(event)
        {
          component: :cache,
          event_type: event.event_type,
          recorded_at: event.recorded_at,
          detail: cache_detail(event),
          correlation_id: event.correlation_id,
          error_class: event.error_class
        }
      end

      def normalize_cable(event)
        {
          component: :cable,
          event_type: event.event_type,
          recorded_at: event.recorded_at,
          detail: cable_detail(event),
          correlation_id: event.correlation_id,
          error_class: event.error_class
        }
      end

      def cache_detail(event)
        digest = event.key_digest.to_s
        digest = "#{digest.first(10)}…" if digest.length > 10
        digest
      end

      def cable_detail(event)
        event.channel_class.presence || event.broadcasting_digest.to_s.first(10)
      end

      def log_error(component, error)
        return unless defined?(Rails) && Rails.logger

        Rails.logger.warn("UnifiedFeed #{component} error: #{error.message}")
      end
    end
  end
end
