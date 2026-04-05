# frozen_string_literal: true

module SolidObserver
  class JobsController < ApplicationController
    before_action :require_solid_queue

    PER_PAGE = 25

    def index
      set_filter_params
      scope = apply_filters(scope_for_status(@status))
      paginate_jobs(scope)
      load_available_options
    end

    def show
      @execution = find_execution(params[:id])
      return redirect_to jobs_path, alert: "Job not found" unless @execution

      @job = @execution.job
      @status = determine_status(@execution)
    end

    def retry
      id = params[:id]
      execution = SolidQueue::FailedExecution.find_by(id: id)
      return redirect_to jobs_path, alert: "Failed job not found" unless execution

      execution.retry
      redirect_to jobs_path(status: "failed"), notice: "Job #{id} queued for retry"
    end

    def discard
      id = params[:id]
      execution = SolidQueue::FailedExecution.find_by(id: id)
      return redirect_to jobs_path, alert: "Failed job not found" unless execution

      execution.discard
      redirect_to jobs_path(status: "failed"), notice: "Job #{id} discarded"
    end

    private

    def set_filter_params
      @status = params[:status].presence || "ready"
      @queue_name = params[:queue_name].presence
      @job_class = params[:job_class].presence
      @page = (params[:page].presence || 1).to_i
    end

    def apply_filters(scope)
      scope = apply_queue_filter(scope, @status, @queue_name)
      scope = scope.joins(:job).where(solid_queue_jobs: {class_name: @job_class}) if @job_class.present?
      scope
    end

    def paginate_jobs(scope)
      @total_count = scope.count
      @total_pages = (@total_count.to_f / PER_PAGE).ceil
      normalize_page
      offset = (@page - 1) * PER_PAGE
      @jobs = scope.order(created_at: :desc).limit(PER_PAGE).offset(offset).includes(:job).to_a
    end

    def normalize_page
      @page = 1 if @page < 1
      @page = 1 if @page > @total_pages && @total_pages > 0
    end

    def load_available_options
      @available_queues = fetch_available_queues
      @available_job_classes = fetch_available_job_classes
    end

    def scope_for_status(status)
      case status.to_s.downcase
      when "scheduled" then SolidQueue::ScheduledExecution.all
      when "claimed" then SolidQueue::ClaimedExecution.all
      when "failed" then SolidQueue::FailedExecution.all
      else SolidQueue::ReadyExecution.all
      end
    end

    def apply_queue_filter(scope, status, queue_name)
      return scope if queue_name.blank?

      case status.to_s.downcase
      when "failed", "claimed"
        scope.joins(:job).where(solid_queue_jobs: {queue_name: queue_name})
      else
        scope.where(queue_name: queue_name)
      end
    end

    def fetch_available_queues
      return [] unless defined?(SolidQueue::Queue)

      SolidQueue::Queue.all.map(&:name)
    rescue
      []
    end

    def fetch_available_job_classes
      SolidQueue::Job.distinct.pluck(:class_name).compact.sort
    rescue
      []
    end

    def find_execution(id)
      SolidQueue::ReadyExecution.find_by(id: id) ||
        SolidQueue::ScheduledExecution.find_by(id: id) ||
        SolidQueue::ClaimedExecution.find_by(id: id) ||
        SolidQueue::FailedExecution.find_by(id: id)
    end
  end
end
