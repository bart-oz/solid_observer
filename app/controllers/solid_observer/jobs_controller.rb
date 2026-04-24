# frozen_string_literal: true

module SolidObserver
  class JobsController < ApplicationController
    include Paginatable
    include RequireSolidQueue

    PER_PAGE = 25
    CACHE_KEY_QUEUES = "solid_observer/jobs/available_queues"
    CACHE_KEY_JOB_CLASSES = "solid_observer/jobs/available_job_classes"

    def index
      filter = Params::JobsFilter.from_params(params)
      @status = filter.status
      @queue_name = filter.queue_name
      @job_class = filter.job_class
      @page = filter.page
      scope = Queries::JobExecutionsQuery.new(filter).call
      offset = paginate_scope(scope, per_page: PER_PAGE)
      @jobs = scope.limit(PER_PAGE).offset(offset).includes(:job).to_a
      @available_queues = fetch_available_queues
      @available_job_classes = fetch_available_job_classes
    end

    def show
      @execution = Queries::ExecutionFinder.find_any(params[:id])
      return redirect_to jobs_path, alert: "Job not found" unless @execution

      presenter = ExecutionPresenter.new(@execution)
      @job = presenter.job
      @status = presenter.status
    end

    def retry
      id = params[:id]
      execution = Queries::ExecutionFinder.find_failed(id)
      return redirect_to(jobs_path, alert: "Failed job not found") unless execution

      execution.retry
      redirect_to jobs_path(status: "failed"), notice: "Job #{id} queued for retry"
    end

    def discard
      id = params[:id]
      execution = Queries::ExecutionFinder.find_failed(id)
      return redirect_to(jobs_path, alert: "Failed job not found") unless execution

      execution.discard
      redirect_to jobs_path(status: "failed"), notice: "Job #{id} discarded"
    end

    private

    def fetch_available_queues
      Rails.cache.fetch(CACHE_KEY_QUEUES, expires_in: SolidObserver.config.filter_cache_ttl) do
        next [] unless defined?(SolidQueue::Queue)
        SolidQueue::Queue.all.map(&:name)
      end
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      []
    end

    def fetch_available_job_classes
      Rails.cache.fetch(CACHE_KEY_JOB_CLASSES, expires_in: SolidObserver.config.filter_cache_ttl) do
        SolidQueue::Job.distinct.pluck(:class_name).compact.sort
      end
    rescue ActiveRecord::StatementInvalid, ActiveRecord::ConnectionNotEstablished
      []
    end
  end
end
