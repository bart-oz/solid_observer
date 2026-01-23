# frozen_string_literal: true

namespace :solid_observer do
  desc "Display SolidObserver status with queue statistics"
  task status: :environment do
    SolidObserver::CLI::Status.call
  end

  desc "Display storage information and database statistics"
  task storage: :environment do
    SolidObserver::CLI::Storage.call
  end

  desc "List jobs with optional filters (status, queue, class, limit)"
  task :jobs, [:status, :queue, :job_class, :limit] => :environment do |_t, args|
    SolidObserver::CLI::Jobs.new.list(
      status: args[:status],
      queue: args[:queue],
      job_class: args[:job_class],
      limit: args[:limit] || 20
    )
  end

  namespace :jobs do
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
