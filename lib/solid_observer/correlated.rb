# frozen_string_literal: true

module SolidObserver
  module Correlated
    def self.included(base)
      base.around_perform do |job, block|
        SolidObserver::Correlated.stamp(job.job_id) { block.call }
      end
    end

    def self.stamp(correlation_id)
      thread_local = Thread.current
      previous = thread_local[:solid_observer_correlation_id]
      thread_local[:solid_observer_correlation_id] = correlation_id if correlation_id.present?

      yield
    ensure
      thread_local[:solid_observer_correlation_id] = previous
    end
  end
end

ActiveSupport.on_load(:active_job) { include SolidObserver::Correlated }
