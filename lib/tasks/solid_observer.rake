# frozen_string_literal: true

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
      Rake::Task["railties:install:migrations"].reenable
      Rake::Task["railties:install:migrations"].invoke
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
    desc "Flush the event buffer to the database"
    task flush: :environment do
      buffer = SolidObserver::QueueEventBuffer.instance
      buffer_size = buffer.size

      if buffer_size.zero?
        puts "Buffer is empty, nothing to flush"
      else
        puts "Flushing #{buffer_size} events from buffer..."
        buffer.flush!
        puts "✓ Buffer flushed successfully"
      end
    end

    desc "Clear the event buffer without flushing to database"
    task clear: :environment do
      buffer = SolidObserver::QueueEventBuffer.instance
      buffer_size = buffer.size

      if buffer_size.zero?
        puts "Buffer is already empty"
      else
        buffer.clear
        puts "✓ Cleared #{buffer_size} events from buffer (not saved to database)"
      end
    end
  end

  namespace :storage do
    desc "Run storage cleanup based on retention policy"
    task cleanup: :environment do
      retention = SolidObserver.config.event_retention
      puts "Running storage cleanup (retention: #{retention.inspect})..."

      deleted_count = SolidObserver::Services::CleanupStorage.call
      puts "✓ Cleanup complete: #{deleted_count} old events deleted"
    end

    desc "Purge ALL SolidObserver storage data (use with caution!)"
    task purge: :environment do
      print "⚠️  This will delete ALL SolidObserver data (events + snapshots). Are you sure? (y/N) "
      $stdout.flush

      confirmation = $stdin.gets&.strip&.downcase
      if confirmation == "y"
        event_count = SolidObserver::QueueEvent.count
        snapshot_count = SolidObserver::StorageInfo.count

        SolidObserver::QueueEvent.delete_all
        SolidObserver::StorageInfo.delete_all

        connection = SolidObserver::QueueEvent.connection
        case connection.adapter_name.downcase
        when "sqlite"
          connection.execute("VACUUM")
          puts "✓ Database vacuumed to reclaim disk space"
        when "postgresql"
          connection.execute("ANALYZE solid_observer_queue_events")
          connection.execute("ANALYZE solid_observer_storage_info")
          puts "✓ Database tables analyzed"
        end

        puts "✓ Purged #{event_count} events and #{snapshot_count} storage snapshots"
      else
        puts "Aborted"
      end
    end
  end

  desc "Display SolidObserver status with queue statistics"
  task status: :environment do
    SolidObserver::CLI::Status.call
  end

  desc "Display storage information and database statistics"
  task storage: :environment do
    SolidObserver::CLI::Storage.call
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
end
