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

    def queue_name
      responded, value = value_from(@execution, :queue_name)
      return value if responded

      value_from(job, :queue_name).last
    end

    def priority
      responded, value = value_from(@execution, :priority)
      return value if responded

      value_from(job, :priority).last
    end

    def to_model
      @execution
    end

    private

    def value_from(target, method_name)
      return [false, nil] unless target&.respond_to?(method_name)

      [true, target.method(method_name).call]
    end
  end
end
