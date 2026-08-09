# frozen_string_literal: true

require_relative "../solid_observer/services/install_migrations"
require_relative "../solid_observer/services/evaluate_alerts"
require_relative "../solid_observer/services/alert_status"

namespace :solid_observer do
  desc "Display SolidObserver version"
  task :version do
    puts "SolidObserver #{SolidObserver::VERSION}"
    puts "Ruby: #{SolidObserver::RUBY_MINIMUM_VERSION}+"
    puts "Rails: #{SolidObserver::RAILS_MINIMUM_VERSION}+"
  end

  namespace :install do
    desc "Copy SolidObserver migrations to your application"
    task migrations: :environment do
      result = SolidObserver::Services::InstallMigrations.call

      if result[:copied].any?
        suffix = (result[:copied].size == 1) ? "" : "s"
        puts "Copied #{result[:copied].size} SolidObserver migration#{suffix} to #{result[:destination]}/"
      else
        puts "No new SolidObserver migrations to copy (all already present in #{result[:destination]}/)"
      end
    end
  end

  namespace :db do
    desc "Create the SolidObserver database"
    task create: :environment do
      config = ActiveRecord::Base.configurations.configs_for(env_name: Rails.env, name: "solid_observer_queue")
      ActiveRecord::Tasks::DatabaseTasks.create(config)
      puts "Created database '#{config.database}'"
    end

    desc "Migrate the SolidObserver database"
    task migrate: :environment do
      ActiveRecord::Tasks::DatabaseTasks.migrate
      puts "Migrations complete"
    end
  end

  namespace :buffer do
    desc "Flush the event buffers to the database"
    task flush: :environment do
      buffers = [
        {label: "queue events", buffer: SolidObserver::QueueEventBuffer.instance},
        {label: "cache events", buffer: SolidObserver::CacheEventBuffer.instance},
        {label: "cache metric buckets", buffer: SolidObserver::CacheMetricBuffer.instance}
      ]
      buffer_sizes = buffers.to_h { |entry| [entry, entry[:buffer].size] }

      if buffer_sizes.values.sum.zero?
        puts "Buffers are empty, nothing to flush"
      else
        buffers.each do |entry|
          size = buffer_sizes.fetch(entry)
          next if size.zero?

          puts "Flushing #{size} #{entry[:label]} from buffer..."
          entry[:buffer].flush!
        end
        puts "✓ Buffers flushed successfully"
      end
    end

    desc "Clear the event buffers without flushing to database"
    task clear: :environment do
      buffers = [
        {label: "queue events", buffer: SolidObserver::QueueEventBuffer.instance},
        {label: "cache events", buffer: SolidObserver::CacheEventBuffer.instance},
        {label: "cache metric buckets", buffer: SolidObserver::CacheMetricBuffer.instance}
      ]
      buffer_sizes = buffers.to_h { |entry| [entry, entry[:buffer].size] }

      if buffer_sizes.values.sum.zero?
        puts "Buffers are already empty"
      else
        buffers.each do |entry|
          size = buffer_sizes.fetch(entry)
          next if size.zero?

          entry[:buffer].clear
          puts "✓ Cleared #{size} #{entry[:label]} from buffer (not saved to database)"
        end
      end
    end
  end

  namespace :cache do
    desc "Clear all SolidCache entries after confirmation"
    task clear: :environment do
      if !SolidObserver::Services::CacheOperations.available?
        puts SolidObserver::Services::CacheOperations.unavailable_message
        next
      end

      print "#{SolidObserver::Services::CacheOperations.message(:clear, :confirmation)} (y/N) "
      $stdout.flush

      if $stdin.gets&.strip&.downcase == "y"
        puts SolidObserver::Services::CacheOperations.clear[:message]
      else
        puts "Aborted"
      end
    end

    desc "Prune expired SolidCache entries"
    task prune: :environment do
      if !SolidObserver::Services::CacheOperations.available?
        puts SolidObserver::Services::CacheOperations.unavailable_message
        next
      end

      puts SolidObserver::Services::CacheOperations.prune[:message]
    end
  end

  namespace :cable do
    desc "Trim expired Solid Cable messages"
    task trim: :environment do
      if !SolidObserver::Services::CableOperations.available?
        puts SolidObserver::Services::CableOperations.unavailable_message
        next
      end

      puts SolidObserver::Services::CableOperations.trim[:message]
    end
  end

  namespace :storage do
    desc "Run storage cleanup based on retention policy"
    task cleanup: :environment do
      retention = SolidObserver.config.event_retention
      puts "Running storage cleanup (retention: #{retention.inspect})..."

      deleted_count = SolidObserver::Services::CleanupStorage.call
      puts "✓ Cleanup complete: #{deleted_count} old telemetry rows deleted"
    end

    desc "Purge ALL SolidObserver storage data (use with caution!)"
    task purge: :environment do
      print "⚠️  This will delete ALL SolidObserver data (events + snapshots). Are you sure? (y/N) "
      $stdout.flush

      confirmation = $stdin.gets&.strip&.downcase
      if confirmation == "y"
        data_source_exists = lambda do |model|
          table_name = model.table_name.to_s
          !table_name.empty? && model.connection.data_source_exists?(table_name)
        rescue ActiveRecord::ConnectionNotEstablished, ActiveRecord::StatementInvalid, TypeError
          false
        end

        telemetry_models = [
          {label: :queue_events, model: SolidObserver::QueueEvent},
          {label: :cache_events, model: SolidObserver::CacheEvent},
          {label: :cache_metrics, model: SolidObserver::CacheMetric}
        ]

        telemetry_counts = telemetry_models.to_h do |entry|
          count = data_source_exists.call(entry[:model]) ? entry[:model].count : 0
          [entry[:label], count]
        end
        snapshot_count = SolidObserver::StorageInfo.count

        telemetry_models.each do |entry|
          next unless data_source_exists.call(entry[:model])

          entry[:model].delete_all
        end
        SolidObserver::StorageInfo.delete_all

        connection = SolidObserver::QueueEvent.connection
        case connection.adapter_name.downcase
        when "sqlite"
          connection.execute("VACUUM")
          puts "✓ Database vacuumed to reclaim disk space"
        when "postgresql"
          [
            SolidObserver::QueueEvent.table_name,
            SolidObserver::StorageInfo.table_name,
            (SolidObserver::CacheEvent.table_name if data_source_exists.call(SolidObserver::CacheEvent)),
            (SolidObserver::CacheMetric.table_name if data_source_exists.call(SolidObserver::CacheMetric))
          ].compact.each do |table_name|
            connection.execute("ANALYZE #{table_name}")
          end
          puts "✓ Database tables analyzed"
        end

        puts(
          "✓ Purged #{telemetry_counts.fetch(:queue_events)} queue events, " \
          "#{telemetry_counts.fetch(:cache_events)} cache events, " \
          "#{telemetry_counts.fetch(:cache_metrics)} cache metrics, " \
          "and #{snapshot_count} storage snapshots"
        )
      else
        puts "Aborted"
      end
    end
  end

  desc "Display SolidObserver status with queue statistics"
  task status: :environment do
    SolidObserver::CLI::Status.call
  end

  desc "Display aggregate and per-component health status"
  task health: :environment do
    SolidObserver::CLI::Health.call
  end

  desc "Display storage information and database statistics"
  task storage: :environment do
    SolidObserver::CLI::Storage.call
  end

  desc "Show the cross-component trace for a correlation_id"
  task :trace, [:correlation_id, :limit] => :environment do |_t, args|
    if args[:correlation_id].nil?
      puts "Error: correlation_id required. Usage: rails solid_observer:trace[CORRELATION_ID,LIMIT]"
      exit 1
    end

    SolidObserver::CLI::Trace.call(correlation_id: args[:correlation_id], limit: args[:limit])
  end

  namespace :jobs do
    desc "List jobs with optional filters (status, queue, class, limit)"
    task :list, [:status, :queue, :job_class, :limit] => :environment do |_t, args|
      SolidObserver::CLI::Jobs.new.list(
        status: args[:status],
        queue: args[:queue],
        job_class: args[:job_class],
        limit: args[:limit] || 20
      )
    end

    desc "Show details for a specific job by ID"
    task :show, [:job_id] => :environment do |_t, args|
      if args[:job_id].nil?
        puts "Error: Job ID required. Usage: rails solid_observer:jobs:show[JOB_ID]"
        exit 1
      end

      SolidObserver::CLI::Jobs.new.show(args[:job_id])
    end

    desc "Retry a failed job by ID"
    task :retry, [:job_id] => :environment do |_t, args|
      if args[:job_id].nil?
        puts "Error: Job ID required. Usage: rails solid_observer:jobs:retry[JOB_ID]"
        exit 1
      end

      SolidObserver::CLI::Jobs.new.retry_job(args[:job_id])
    end
    desc "Discard a failed job by ID"
    task :discard, [:job_id] => :environment do |_t, args|
      if args[:job_id].nil?
        puts "Error: Job ID required. Usage: rails solid_observer:jobs:discard[JOB_ID]"
        exit 1
      end

      SolidObserver::CLI::Jobs.new.discard(args[:job_id])
    end
  end
  namespace :alerts do
    desc "Evaluate all enabled alert rules"
    task evaluate: :environment do
      result = SolidObserver::Services::EvaluateAlerts.call
      if result[:skipped]
        puts "Alert evaluation skipped: #{result[:skipped]}"
      else
        puts "Alert evaluation complete: #{result[:triggered]} triggered, #{result[:resolved]} resolved."
      end
    end
  end
end
