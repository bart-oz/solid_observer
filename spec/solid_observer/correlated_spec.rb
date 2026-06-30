# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::Correlated do
  describe "ActiveJob around_perform propagation" do
    it "stamps the job's correlation id around perform and restores prior value" do
      captured = nil

      job_class = Class.new(ActiveJob::Base) do
        define_method(:perform) do
          captured = Thread.current[:solid_observer_correlation_id]
        end
      end

      job = job_class.new
      prior_correlation_id = Thread.current[:solid_observer_correlation_id]

      job.perform_now

      expect(captured).to eq(job.job_id)
      expect(Thread.current[:solid_observer_correlation_id]).to eq(prior_correlation_id)
    end

    it "restores the prior correlation id even when perform raises" do
      prior_correlation_id = "prior-#{SecureRandom.uuid}"
      Thread.current[:solid_observer_correlation_id] = prior_correlation_id

      job_class = Class.new(ActiveJob::Base) do
        define_method(:perform) do
          raise StandardError, "boom"
        end
      end

      expect {
        job_class.new.perform_now
      }.to raise_error(StandardError, "boom")

      expect(Thread.current[:solid_observer_correlation_id]).to eq(prior_correlation_id)
    ensure
      Thread.current[:solid_observer_correlation_id] = nil
    end

    it "handles nested jobs without leaking correlation state" do
      outer_values = []
      inner_values = []

      inner_class = Class.new(ActiveJob::Base) do
        define_method(:perform) do
          inner_values << Thread.current[:solid_observer_correlation_id]
        end
      end

      outer_class = Class.new(ActiveJob::Base) do
        define_method(:perform) do
          outer_values << Thread.current[:solid_observer_correlation_id]
          inner_class.new.perform_now
          outer_values << Thread.current[:solid_observer_correlation_id]
        end
      end

      outer_job = outer_class.new
      outer_job.perform_now

      expect(outer_values).to eq([outer_job.job_id, outer_job.job_id])
      expect(inner_values.first).not_to eq(outer_job.job_id)
      expect(inner_values.first).to be_present
    end

    it "does not stamp thread-local correlation id when job lacks a job_id" do
      captured = :unset

      job_class = Class.new(ActiveJob::Base) do
        define_method(:perform) do
          captured = Thread.current[:solid_observer_correlation_id]
        end
      end

      job = job_class.new
      allow(job).to receive(:job_id).and_return(nil)
      job.perform_now

      expect(captured).to be_nil
    end
  end
end
