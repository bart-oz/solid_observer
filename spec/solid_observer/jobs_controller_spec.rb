# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::JobsController do
  after { SolidObserver.reset_configuration! }

  let(:controller) { described_class.allocate }

  before do
    stub_const("SolidQueue", Module.new)
    stub_const("SolidQueue::Job", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::ReadyExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::ScheduledExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::ClaimedExecution", Class.new(ActiveRecord::Base))
    stub_const("SolidQueue::FailedExecution", Class.new(ActiveRecord::Base))
  end

  describe "class structure" do
    it "inherits from ApplicationController" do
      expect(described_class.superclass).to eq(SolidObserver::ApplicationController)
    end

    it "registers :require_solid_queue as a before_action" do
      callbacks = described_class._process_action_callbacks.map(&:filter)
      expect(callbacks).to include(:require_solid_queue)
    end

    it "defines PER_PAGE as 25" do
      expect(described_class::PER_PAGE).to eq(25)
    end
  end

  describe "#set_filter_params" do
    it "defaults @status to 'ready'" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@status)).to eq("ready")
    end

    it "reads status from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(status: "failed"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@status)).to eq("failed")
    end

    it "reads queue_name from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(queue_name: "default"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@queue_name)).to eq("default")
    end

    it "reads job_class from params" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(job_class: "MyJob"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@job_class)).to eq("MyJob")
    end

    it "defaults @page to 1" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@page)).to eq(1)
    end

    it "converts page param to integer" do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new(page: "3"))
      controller.send(:set_filter_params)
      expect(controller.instance_variable_get(:@page)).to eq(3)
    end
  end

  describe "#scope_for_status" do
    it "returns ReadyExecution for 'ready'" do
      ready_scope = double("ready_scope")
      allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
      expect(controller.send(:scope_for_status, "ready")).to eq(ready_scope)
    end

    it "returns ScheduledExecution for 'scheduled'" do
      sched_scope = double("sched_scope")
      allow(SolidQueue::ScheduledExecution).to receive(:all).and_return(sched_scope)
      expect(controller.send(:scope_for_status, "scheduled")).to eq(sched_scope)
    end

    it "returns ClaimedExecution for 'claimed'" do
      claimed_scope = double("claimed_scope")
      allow(SolidQueue::ClaimedExecution).to receive(:all).and_return(claimed_scope)
      expect(controller.send(:scope_for_status, "claimed")).to eq(claimed_scope)
    end

    it "returns FailedExecution for 'failed'" do
      failed_scope = double("failed_scope")
      allow(SolidQueue::FailedExecution).to receive(:all).and_return(failed_scope)
      expect(controller.send(:scope_for_status, "failed")).to eq(failed_scope)
    end

    it "defaults to ReadyExecution for unknown status" do
      ready_scope = double("ready_scope")
      allow(SolidQueue::ReadyExecution).to receive(:all).and_return(ready_scope)
      expect(controller.send(:scope_for_status, "unknown_status")).to eq(ready_scope)
    end
  end

  describe "#apply_queue_filter" do
    let(:scope) { double("scope") }

    it "returns scope unchanged when queue_name is blank" do
      expect(controller.send(:apply_queue_filter, scope, "ready", nil)).to eq(scope)
    end

    it "filters by queue_name directly for ready status" do
      filtered = double("filtered")
      allow(scope).to receive(:where).with(queue_name: "default").and_return(filtered)
      expect(controller.send(:apply_queue_filter, scope, "ready", "default")).to eq(filtered)
    end

    it "joins through job table for failed status" do
      joined = double("joined")
      filtered = double("filtered")
      allow(scope).to receive(:joins).with(:job).and_return(joined)
      allow(joined).to receive(:where).with(solid_queue_jobs: {queue_name: "default"}).and_return(filtered)
      expect(controller.send(:apply_queue_filter, scope, "failed", "default")).to eq(filtered)
    end

    it "joins through job table for claimed status" do
      joined = double("joined")
      filtered = double("filtered")
      allow(scope).to receive(:joins).with(:job).and_return(joined)
      allow(joined).to receive(:where).with(solid_queue_jobs: {queue_name: "urgent"}).and_return(filtered)
      expect(controller.send(:apply_queue_filter, scope, "claimed", "urgent")).to eq(filtered)
    end
  end

  describe "#apply_filters" do
    let(:scope) { double("scope") }

    before do
      controller.instance_variable_set(:@queue_name, nil)
      controller.instance_variable_set(:@job_class, nil)
      controller.instance_variable_set(:@status, "ready")
    end

    it "returns scope unchanged when no filters set" do
      expect(controller.send(:apply_filters, scope)).to eq(scope)
    end

    it "joins job table and filters by class_name when job_class present" do
      controller.instance_variable_set(:@job_class, "MyJob")
      joined = double("joined")
      filtered = double("filtered")
      allow(scope).to receive(:joins).with(:job).and_return(joined)
      allow(joined).to receive(:where).with(solid_queue_jobs: {class_name: "MyJob"}).and_return(filtered)
      expect(controller.send(:apply_filters, scope)).to eq(filtered)
    end
  end

  describe "#find_execution" do
    it "returns ReadyExecution when found" do
      exec = double("execution")
      allow(SolidQueue::ReadyExecution).to receive(:find_by).with(id: "1").and_return(exec)
      expect(controller.send(:find_execution, "1")).to eq(exec)
    end

    it "checks other types when ReadyExecution not found" do
      allow(SolidQueue::ReadyExecution).to receive(:find_by).and_return(nil)
      exec = double("execution")
      allow(SolidQueue::ScheduledExecution).to receive(:find_by).with(id: "2").and_return(exec)
      allow(SolidQueue::ClaimedExecution).to receive(:find_by).and_return(nil)
      allow(SolidQueue::FailedExecution).to receive(:find_by).and_return(nil)
      expect(controller.send(:find_execution, "2")).to eq(exec)
    end

    it "returns nil when not found in any execution type" do
      allow(SolidQueue::ReadyExecution).to receive(:find_by).and_return(nil)
      allow(SolidQueue::ScheduledExecution).to receive(:find_by).and_return(nil)
      allow(SolidQueue::ClaimedExecution).to receive(:find_by).and_return(nil)
      allow(SolidQueue::FailedExecution).to receive(:find_by).and_return(nil)
      expect(controller.send(:find_execution, "999")).to be_nil
    end
  end

  describe "#show" do
    context "when execution is found" do
      let(:execution) { double("execution", class: SolidQueue::ReadyExecution) }
      let(:job) { double("job") }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "1"))
        allow(controller).to receive(:find_execution).with("1").and_return(execution)
        allow(execution).to receive(:job).and_return(job)
        allow(execution).to receive(:class).and_return(SolidQueue::ReadyExecution)
      end

      it "assigns @execution" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@execution)).to eq(execution)
      end

      it "assigns @job" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@job)).to eq(job)
      end

      it "assigns @status via determine_status" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@status)).to eq("ready")
      end
    end

    context "when execution is not found" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "999"))
        allow(controller).to receive(:find_execution).with("999").and_return(nil)
        controller.define_singleton_method(:jobs_path) { "/solid_observer/jobs" }
      end

      it "redirects with an alert" do
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", alert: "Job not found")
        controller.send(:show)
      end
    end
  end

  describe "#retry" do
    context "when failed execution exists" do
      let(:execution) { double("execution") }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "5"))
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "5").and_return(execution)
        controller.define_singleton_method(:jobs_path) { |**| "/solid_observer/jobs" }
      end

      it "calls retry on the execution" do
        allow(controller).to receive(:redirect_to)
        expect(execution).to receive(:retry)
        controller.send(:retry)
      end

      it "redirects with a notice" do
        allow(execution).to receive(:retry)
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", notice: "Job 5 queued for retry")
        controller.send(:retry)
      end
    end

    context "when failed execution is not found" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "999"))
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "999").and_return(nil)
        controller.define_singleton_method(:jobs_path) { "/solid_observer/jobs" }
      end

      it "redirects with an alert" do
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", alert: "Failed job not found")
        controller.send(:retry)
      end
    end
  end

  describe "#discard" do
    context "when failed execution exists" do
      let(:execution) { double("execution") }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "7"))
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "7").and_return(execution)
        controller.define_singleton_method(:jobs_path) { |**| "/solid_observer/jobs" }
      end

      it "calls discard on the execution" do
        allow(controller).to receive(:redirect_to)
        expect(execution).to receive(:discard)
        controller.send(:discard)
      end

      it "redirects with a notice" do
        allow(execution).to receive(:discard)
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", notice: "Job 7 discarded")
        controller.send(:discard)
      end
    end

    context "when failed execution is not found" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "999"))
        allow(SolidQueue::FailedExecution).to receive(:find_by).with(id: "999").and_return(nil)
        controller.define_singleton_method(:jobs_path) { "/solid_observer/jobs" }
      end

      it "redirects with an alert" do
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", alert: "Failed job not found")
        controller.send(:discard)
      end
    end
  end

  describe "#fetch_available_queues" do
    context "when SolidQueue::Queue is defined" do
      before { stub_const("SolidQueue::Queue", Class.new(ActiveRecord::Base)) }

      it "returns queue names" do
        q1 = double("q1", name: "default")
        q2 = double("q2", name: "urgent")
        allow(SolidQueue::Queue).to receive(:all).and_return([q1, q2])
        expect(controller.send(:fetch_available_queues)).to eq(["default", "urgent"])
      end
    end

    context "when SolidQueue::Queue is not defined" do
      it "returns empty array" do
        expect(controller.send(:fetch_available_queues)).to eq([])
      end
    end

    context "on ActiveRecord error" do
      before do
        stub_const("SolidQueue::Queue", Class.new(ActiveRecord::Base))
        allow(SolidQueue::Queue).to receive(:all).and_raise(ActiveRecord::StatementInvalid)
      end

      it "returns empty array" do
        expect(controller.send(:fetch_available_queues)).to eq([])
      end
    end
  end

  describe "#fetch_available_job_classes" do
    it "returns distinct sorted class names" do
      distinct = double("distinct")
      allow(SolidQueue::Job).to receive(:distinct).and_return(distinct)
      allow(distinct).to receive(:pluck).with(:class_name).and_return(["MyJob", nil, "AnotherJob"])
      expect(controller.send(:fetch_available_job_classes)).to eq(["AnotherJob", "MyJob"])
    end

    it "returns empty array on ActiveRecord error" do
      allow(SolidQueue::Job).to receive(:distinct).and_raise(ActiveRecord::StatementInvalid)
      expect(controller.send(:fetch_available_job_classes)).to eq([])
    end
  end
end
