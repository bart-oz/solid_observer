# frozen_string_literal: true

module SolidObserver
  class ExecutionPresenter
    STATUS_MAP = {
      "SolidQueue::ReadyExecution" => "ready",
      "SolidQueue::ScheduledExecution" => "scheduled",
      "SolidQueue::ClaimedExecution" => "claimed",
      "SolidQueue::FailedExecution" => "failed"
    }.freeze

    def initialize(execution)
      @execution = execution
    end

    def status
      STATUS_MAP.fetch(@execution.class.name, "unknown")
    end

    def job
      @execution.job
    end

    def to_model
      @execution
    end
  end
end
