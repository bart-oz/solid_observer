# frozen_string_literal: true

module SolidObserver
  module Queries
    class ExecutionFinder
      EXECUTION_TYPES = [
        "SolidQueue::ReadyExecution",
        "SolidQueue::ScheduledExecution",
        "SolidQueue::ClaimedExecution",
        "SolidQueue::FailedExecution"
      ].freeze

      STATUS_TO_EXECUTION_TYPE = {
        "ready" => "SolidQueue::ReadyExecution",
        "scheduled" => "SolidQueue::ScheduledExecution",
        "claimed" => "SolidQueue::ClaimedExecution",
        "failed" => "SolidQueue::FailedExecution"
      }.freeze

      def self.find_any(id)
        EXECUTION_TYPES.each do |const_name|
          execution = const_name.safe_constantize&.find_by(id: id)
          return execution if execution
        end
        nil
      end

      def self.find_by_status(id, status)
        const_name = STATUS_TO_EXECUTION_TYPE[status.to_s.downcase]
        return nil unless const_name

        const_name.safe_constantize&.find_by(id: id)
      end

      def self.find_failed(id)
        return nil unless defined?(SolidQueue::FailedExecution)

        SolidQueue::FailedExecution.find_by(id: id)
      end
    end
  end
end
