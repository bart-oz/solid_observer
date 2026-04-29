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
      result = Queries::JobExecutionsQuery.new(filter).call
      offset = paginate_scope(result, per_page: PER_PAGE)
      @jobs = if result.is_a?(Array)
        result.drop(offset).first(PER_PAGE)
      else
        result.limit(PER_PAGE).offset(offset).includes(:job).to_a
      end
      @available_queues = fetch_available_queues
      @available_job_classes = fetch_available_job_classes
    end

    def show
      @execution = find_execution_for_show
      return redirect_to jobs_path, alert: "Job not found" unless @execution

      assign_show_presenter
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

    def find_execution_for_show
      id = params[:id]
      Queries::ExecutionFinder.find_by_status(id, params[:status]) ||
        Queries::ExecutionFinder.find_any(id)
    end

    def assign_show_presenter
      presenter = ExecutionPresenter.new(@execution)
      @job = presenter.job
      @status = presenter.status
    end

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
