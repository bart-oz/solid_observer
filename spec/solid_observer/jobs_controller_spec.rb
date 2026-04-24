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

  describe "#index" do
    let(:filter) do
      instance_double(
        SolidObserver::Params::JobsFilter,
        page: 2,
        status: "ready",
        queue_name: "default",
        job_class: "MyJob"
      )
    end
    let(:scope) { double("scope") }
    let(:limited_scope) { double("limited_scope") }
    let(:offset_scope) { double("offset_scope") }
    let(:jobs) { [double("execution")] }
    let(:query) { instance_double(SolidObserver::Queries::JobExecutionsQuery, call: scope) }

    before do
      allow(controller).to receive(:params).and_return(ActionController::Parameters.new({}))
      allow(SolidObserver::Params::JobsFilter).to receive(:from_params).and_return(filter)
      allow(SolidObserver::Queries::JobExecutionsQuery).to receive(:new).with(filter).and_return(query)
      allow(controller).to receive(:paginate_scope).with(scope, per_page: described_class::PER_PAGE).and_return(25)
      allow(scope).to receive(:limit).with(described_class::PER_PAGE).and_return(limited_scope)
      allow(limited_scope).to receive(:offset).with(25).and_return(offset_scope)
      allow(offset_scope).to receive(:includes).with(:job).and_return(jobs)
      allow(controller).to receive(:fetch_available_queues).and_return(["default"])
      allow(controller).to receive(:fetch_available_job_classes).and_return(["MyJob"])
    end

    it "assigns @jobs" do
      controller.send(:index)
      expect(controller.instance_variable_get(:@jobs)).to eq(jobs)
    end

    it "assigns legacy filter ivars" do
      controller.send(:index)
      expect(controller.instance_variable_get(:@status)).to eq("ready")
      expect(controller.instance_variable_get(:@queue_name)).to eq("default")
      expect(controller.instance_variable_get(:@job_class)).to eq("MyJob")
    end
  end

  describe "#fetch_available_queues" do
    context "when SolidQueue::Queue is defined" do
      before do
        stub_const("SolidQueue::Queue", Class.new {
          def self.all
          end
        })
      end

      it "returns queue names" do
        q1 = double("q1", name: "default")
        q2 = double("q2", name: "urgent")
        allow(SolidQueue::Queue).to receive(:all).and_return([q1, q2])
        expect(controller.send(:fetch_available_queues)).to eq(["default", "urgent"])
      end
    end

    context "when SolidQueue::Queue is not defined" do
      before { hide_const("SolidQueue::Queue") if defined?(SolidQueue::Queue) }

      it "returns empty array" do
        expect(controller.send(:fetch_available_queues)).to eq([])
      end
    end

    context "on ActiveRecord error" do
      before do
        stub_const("SolidQueue::Queue", Class.new {
          def self.all
          end
        })
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

  describe "#index filter option caching" do
    before do
      SolidObserver.config.filter_cache_ttl = 1.minute
      stub_const("SolidQueue::Queue", Class.new {
        def self.all = []
      })
      allow(SolidQueue::Queue).to receive(:all).and_return([double("q", name: "default")])
      allow(SolidQueue::Job).to receive(:distinct).and_return(
        double("distinct", pluck: ["MyJob"])
      )
    end

    it "calls source once on cold cache" do
      expect(SolidQueue::Queue).to receive(:all).once.and_return([double("q", name: "default")])
      controller.send(:fetch_available_queues)
      controller.send(:fetch_available_queues)
    end

    it "calls job class source once on cold cache" do
      distinct = double("distinct", pluck: ["MyJob"])
      expect(SolidQueue::Job).to receive(:distinct).once.and_return(distinct)
      controller.send(:fetch_available_job_classes)
      controller.send(:fetch_available_job_classes)
    end

    it "re-fetches after TTL expiry" do
      distinct = double("distinct", pluck: ["MyJob"])
      expect(SolidQueue::Job).to receive(:distinct).twice.and_return(distinct)

      controller.send(:fetch_available_job_classes)
      travel_to(2.minutes.from_now) do
        controller.send(:fetch_available_job_classes)
      end
    end
  end

  describe "#show" do
    context "when execution is found" do
      let(:execution) { double("execution") }
      let(:job) { double("job") }
      let(:presenter) { instance_double(SolidObserver::ExecutionPresenter, job: job, status: "ready") }

      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "1"))
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_any).with("1").and_return(execution)
        allow(SolidObserver::ExecutionPresenter).to receive(:new).with(execution).and_return(presenter)
      end

      it "assigns @execution" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@execution)).to eq(execution)
      end

      it "assigns @job" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@job)).to eq(job)
      end

      it "assigns @status from presenter" do
        controller.send(:show)
        expect(controller.instance_variable_get(:@status)).to eq("ready")
      end
    end

    context "when execution is not found" do
      before do
        allow(controller).to receive(:params).and_return(ActionController::Parameters.new(id: "999"))
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_any).with("999").and_return(nil)
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
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_failed).with("5").and_return(execution)
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
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_failed).with("999").and_return(nil)
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
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_failed).with("7").and_return(execution)
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
        allow(SolidObserver::Queries::ExecutionFinder).to receive(:find_failed).with("999").and_return(nil)
        controller.define_singleton_method(:jobs_path) { "/solid_observer/jobs" }
      end

      it "redirects with an alert" do
        expect(controller).to receive(:redirect_to).with("/solid_observer/jobs", alert: "Failed job not found")
        controller.send(:discard)
      end
    end
  end
end
