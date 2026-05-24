# frozen_string_literal: true

module SolidObserver
  class QueueEvent < BaseEvent
    self.table_name = "solid_observer_queue_events"

    EVENT_TYPES = %w[
      job_enqueued
      job_completed
      job_failed
      job_discarded
    ].freeze
    DISTINCT_FILTER_LIMIT = 500

    validates :event_type, presence: true, inclusion: {in: EVENT_TYPES}
    validates :recorded_at, presence: true

    scope :by_job_class, ->(job_class) { where(job_class: job_class) }
    scope :by_queue, ->(queue_name) { where(queue_name: queue_name) }
    scope :by_event_type, ->(event_type) { where(event_type: event_type) }
    scope :since, ->(time) { where("recorded_at >= ?", time) }
    scope :before, ->(time) { where("recorded_at < ?", time) }
    scope :recent, ->(limit = 10) { order(recorded_at: :desc).limit(limit) }
    scope :recent_failures, ->(limit = 5) { by_event_type("job_failed").order(recorded_at: :desc).limit(limit) }
    scope :distinct_job_classes, -> {
      where("recorded_at >= ?", SolidObserver.config.event_retention.ago)
        .where.not(job_class: nil)
        .distinct
        .limit(DISTINCT_FILTER_LIMIT)
        .pluck(:job_class)
        .sort
    }
    scope :distinct_queue_names, -> {
      where("recorded_at >= ?", SolidObserver.config.event_retention.ago)
        .where.not(queue_name: nil)
        .distinct
        .limit(DISTINCT_FILTER_LIMIT)
        .pluck(:queue_name)
        .sort
    }

    def self.performed_count_last(duration)
      by_event_type("job_completed").since(duration.ago).count
    end

    def self.failed_count_last(duration)
      by_event_type("job_failed").since(duration.ago).count
    end

    def self.enqueue_rate_per_minute(window: 5.minutes)
      count = by_event_type("job_enqueued").since(window.ago).count
      return 0.0 if count.zero?

      (count.to_f / (window.to_f / 60.0)).round(1)
    end

    def self.enqueued_count_last(duration)
      by_event_type("job_enqueued").since(duration.ago).count
    end

    def self.avg_duration_last(duration)
      by_event_type("job_completed").since(duration.ago).average(:duration).to_f
    end

    def self.count_by_queue_and_event_type(window:, event_type:)
      since(window.ago)
        .where(event_type: event_type)
        .where.not(queue_name: nil)
        .group(:queue_name)
        .count
    end

    def self.count_by_time_bucket(event_type:, window:, bucket_seconds:)
      context = build_bucket_context(window: window, bucket_seconds: bucket_seconds)
      return [] unless context

      counts_by_bucket = fetch_counts_by_bucket(event_type: event_type, context: context)
      fill_missing_buckets(context: context, counts_by_bucket: counts_by_bucket)
    end

    class << self
      private

      def build_bucket_context(window:, bucket_seconds:)
        bucket_size = bucket_seconds.to_i
        return nil if bucket_size <= 0 || window.to_i <= 0

        end_time = Time.current
        start_time = end_time - window

        {
          bucket_size: bucket_size,
          start_time: start_time,
          end_time: end_time,
          start_bucket: align_bucket(start_time.to_i, bucket_size),
          end_bucket: align_bucket(end_time.to_i, bucket_size)
        }
      end

      def fetch_counts_by_bucket(event_type:, context:)
        rows = fetch_grouped_rows(event_type: event_type, context: context)
        rows.to_h { |row| [row["bucket_time"].to_i, row["bucket_count"].to_i] }
      end

      def fetch_grouped_rows(event_type:, context:)
        pool = BaseEvent.connection_pool
        query_context = context.merge(
          event_type: event_type,
          adapter: pool.db_config.adapter.to_s.downcase
        )

        pool.with_connection do |connection|
          connection.select_all(grouped_counts_sql(connection: connection, query_context: query_context)).to_a
        end
      end

      def grouped_counts_sql(connection:, query_context:)
        <<~SQL.squish
          SELECT #{bucket_time_sql(adapter: query_context[:adapter], bucket_size: query_context[:bucket_size])} AS bucket_time, COUNT(*) AS bucket_count
          FROM #{table_name}
          WHERE event_type = #{connection.quote(query_context[:event_type])}
            AND recorded_at >= #{connection.quote(query_context[:start_time])}
            AND recorded_at <= #{connection.quote(query_context[:end_time])}
          GROUP BY bucket_time
          ORDER BY bucket_time ASC
        SQL
      end

      def bucket_time_sql(adapter:, bucket_size:)
        case adapter
        when "sqlite3", "sqlite"
          "(CAST(strftime('%s', recorded_at) AS INTEGER) / #{bucket_size}) * #{bucket_size}"
        when "postgresql"
          if bucket_size == 60
            "EXTRACT(EPOCH FROM date_trunc('minute', recorded_at))::bigint"
          else
            "(EXTRACT(EPOCH FROM recorded_at)::bigint / #{bucket_size}) * #{bucket_size}"
          end
        when "mysql2", "trilogy", "mysql"
          "(UNIX_TIMESTAMP(recorded_at) DIV #{bucket_size}) * #{bucket_size}"
        else
          raise ArgumentError, "Unsupported adapter for bucket aggregation: #{adapter.inspect}"
        end
      end

      def fill_missing_buckets(context:, counts_by_bucket:)
        context[:start_bucket].step(context[:end_bucket], context[:bucket_size]).map do |timestamp|
          {t: timestamp, v: counts_by_bucket.fetch(timestamp, 0)}
        end
      end

      def align_bucket(value, bucket_size)
        (value / bucket_size) * bucket_size
      end
    end
  end
end
