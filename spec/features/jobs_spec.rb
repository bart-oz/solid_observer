# frozen_string_literal: true

require "feature_helper"

RSpec.describe "Jobs", type: :feature do
  def ensure_solid_queue_tables!
    connection = ActiveRecord::Base.connection

    unless connection.table_exists?(:solid_queue_jobs)
      connection.create_table :solid_queue_jobs do |t|
        t.string :queue_name, null: false
        t.string :class_name, null: false
        t.integer :priority, null: false, default: 0
        t.datetime :created_at, null: false
        t.datetime :updated_at, null: false
      end
    end

    if connection.table_exists?(:solid_queue_jobs) && !connection.column_exists?(:solid_queue_jobs, :priority)
      connection.add_column :solid_queue_jobs, :priority, :integer, null: false, default: 0
    end

    unless connection.table_exists?(:solid_queue_ready_executions)
      connection.create_table :solid_queue_ready_executions do |t|
        t.bigint :job_id, null: false
        t.string :queue_name, null: false
        t.integer :priority, null: false, default: 0
        t.datetime :created_at, null: false
      end
    end

    unless connection.table_exists?(:solid_queue_scheduled_executions)
      connection.create_table :solid_queue_scheduled_executions do |t|
        t.bigint :job_id, null: false
        t.string :queue_name, null: false
        t.integer :priority, null: false, default: 0
        t.datetime :scheduled_at, null: false
        t.datetime :created_at, null: false
      end
    end

    unless connection.table_exists?(:solid_queue_claimed_executions)
      connection.create_table :solid_queue_claimed_executions do |t|
        t.bigint :job_id, null: false
        t.bigint :process_id
        t.datetime :created_at, null: false
      end
    end

    unless connection.table_exists?(:solid_queue_failed_executions)
      connection.create_table :solid_queue_failed_executions do |t|
        t.bigint :job_id, null: false
        t.text :error
        t.datetime :created_at, null: false
      end
    end
  end

  def stub_solid_queue_models!
    stub_const("SolidQueue", Module.new)

    job_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_jobs"
    end
    stub_const("SolidQueue::Job", job_model)

    ready_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_ready_executions"
      belongs_to :job, class_name: "SolidQueue::Job"
    end
    stub_const("SolidQueue::ReadyExecution", ready_model)

    scheduled_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_scheduled_executions"
      belongs_to :job, class_name: "SolidQueue::Job"
    end
    stub_const("SolidQueue::ScheduledExecution", scheduled_model)

    claimed_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_claimed_executions"
      belongs_to :job, class_name: "SolidQueue::Job"
    end
    stub_const("SolidQueue::ClaimedExecution", claimed_model)

    failed_model = Class.new(ActiveRecord::Base) do
      self.table_name = "solid_queue_failed_executions"
      belongs_to :job, class_name: "SolidQueue::Job"
    end
    stub_const("SolidQueue::FailedExecution", failed_model)
  end

  context "when SolidQueue is not available" do
    it "redirects to dashboard with an alert" do
      visit "/solid_observer/jobs"
      expect(page.current_path).to match(%r{/solid_observer/?$})
    end

    it "displays the SolidQueue unavailable alert" do
      visit "/solid_observer/jobs"
      expect(page).to have_content("SolidQueue is not available")
    end
  end

  context "when all_active filter is used" do
    before do
      ensure_solid_queue_tables!
      stub_solid_queue_models!
      SolidObserver.config.storage_mode = :persistence

      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::Job.delete_all

      now = Time.current
      ready_job = SolidQueue::Job.create!(queue_name: "default", class_name: "ReadyJob", created_at: now - 5.minutes, updated_at: now - 5.minutes)
      scheduled_job = SolidQueue::Job.create!(queue_name: "mailers", class_name: "ScheduledJob", created_at: now - 4.minutes, updated_at: now - 4.minutes)
      claimed_job = SolidQueue::Job.create!(queue_name: "critical", class_name: "ClaimedJob", created_at: now - 3.minutes, updated_at: now - 3.minutes)
      failed_job = SolidQueue::Job.create!(queue_name: "default", class_name: "FailedJob", created_at: now - 2.minutes, updated_at: now - 2.minutes)

      SolidQueue::ReadyExecution.create!(job: ready_job, queue_name: "default", priority: 0, created_at: now - 5.minutes)
      SolidQueue::ScheduledExecution.create!(job: scheduled_job, queue_name: "mailers", priority: 0, scheduled_at: now + 10.minutes, created_at: now - 4.minutes)
      SolidQueue::ClaimedExecution.create!(job: claimed_job, process_id: 123, created_at: now - 3.minutes)
      SolidQueue::FailedExecution.create!(job: failed_job, error: "failure", created_at: now - 2.minutes)
    end

    after do
      SolidQueue::ReadyExecution.delete_all if defined?(SolidQueue::ReadyExecution)
      SolidQueue::ScheduledExecution.delete_all if defined?(SolidQueue::ScheduledExecution)
      SolidQueue::ClaimedExecution.delete_all if defined?(SolidQueue::ClaimedExecution)
      SolidQueue::FailedExecution.delete_all if defined?(SolidQueue::FailedExecution)
      SolidQueue::Job.delete_all if defined?(SolidQueue::Job)
    end

    it "renders jobs from all four execution tables" do
      visit "/solid_observer/jobs?status=all_active"

      expect(page).to have_content("ReadyJob")
      expect(page).to have_content("ScheduledJob")
      expect(page).to have_content("ClaimedJob")
      expect(page).to have_content("FailedJob")
      expect(page).to have_content("Ready")
      expect(page).to have_content("Scheduled")
      expect(page).to have_content("Claimed")
      expect(page).to have_content("Failed")
    end
  end

  context "when all_active has colliding execution ids across statuses" do
    before do
      ensure_solid_queue_tables!
      stub_solid_queue_models!
      SolidObserver.config.storage_mode = :persistence

      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::Job.delete_all

      now = Time.current
      ready_job = SolidQueue::Job.create!(queue_name: "default", class_name: "ReadyCollisionJob", created_at: now - 2.minutes, updated_at: now - 2.minutes)
      claimed_job = SolidQueue::Job.create!(queue_name: "critical", class_name: "ClaimedCollisionJob", created_at: now - 1.minute, updated_at: now - 1.minute)

      SolidQueue::ReadyExecution.create!(id: 77, job: ready_job, queue_name: "default", priority: 0, created_at: now - 2.minutes)
      SolidQueue::ClaimedExecution.create!(id: 77, job: claimed_job, process_id: 321, created_at: now - 1.minute)
    end

    after do
      SolidQueue::ReadyExecution.delete_all if defined?(SolidQueue::ReadyExecution)
      SolidQueue::ScheduledExecution.delete_all if defined?(SolidQueue::ScheduledExecution)
      SolidQueue::ClaimedExecution.delete_all if defined?(SolidQueue::ClaimedExecution)
      SolidQueue::FailedExecution.delete_all if defined?(SolidQueue::FailedExecution)
      SolidQueue::Job.delete_all if defined?(SolidQueue::Job)
    end

    it "renders distinct status-aware links when ids collide" do
      visit "/solid_observer/jobs?status=all_active"

      ready_href = nil
      claimed_href = nil

      within("tr", text: "ReadyCollisionJob") do
        ready_href = find_link("View")[:href]
      end

      within("tr", text: "ClaimedCollisionJob") do
        claimed_href = find_link("View")[:href]
      end

      expect(ready_href).to include("/solid_observer/jobs/77")
      expect(ready_href).to include("status=ready")
      expect(claimed_href).to include("/solid_observer/jobs/77")
      expect(claimed_href).to include("status=claimed")
      expect(ready_href).not_to eq(claimed_href)
    end
  end

  context "when showing a failed execution" do
    before do
      ensure_solid_queue_tables!
      stub_solid_queue_models!
      SolidObserver.config.storage_mode = :persistence

      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::Job.delete_all

      now = Time.current
      failed_job = SolidQueue::Job.create!(
        queue_name: "critical",
        class_name: "FailedShowJob",
        priority: 9,
        created_at: now - 1.minute,
        updated_at: now - 1.minute
      )
      @failed_execution = SolidQueue::FailedExecution.create!(job: failed_job, error: nil, created_at: now - 1.minute)
    end

    after do
      SolidQueue::ReadyExecution.delete_all if defined?(SolidQueue::ReadyExecution)
      SolidQueue::ScheduledExecution.delete_all if defined?(SolidQueue::ScheduledExecution)
      SolidQueue::ClaimedExecution.delete_all if defined?(SolidQueue::ClaimedExecution)
      SolidQueue::FailedExecution.delete_all if defined?(SolidQueue::FailedExecution)
      SolidQueue::Job.delete_all if defined?(SolidQueue::Job)
    end

    it "renders the show page with queue and priority from the job" do
      visit "/solid_observer/jobs/#{@failed_execution.id}?status=failed"

      expect(page.status_code).to eq(200)

      within("table.so-details") do
        queue_cell = find(:xpath, ".//tr[td[normalize-space()='Queue']]/td[2]")
        priority_cell = find(:xpath, ".//tr[td[normalize-space()='Priority']]/td[2]")

        expect(queue_cell).to have_text("critical")
        expect(priority_cell).to have_text("9")
      end
    end

    it "renders the show page when no status param is given (find_any branch)" do
      visit "/solid_observer/jobs/#{@failed_execution.id}"

      expect(page.status_code).to eq(200)

      within("table.so-details") do
        queue_cell = find(:xpath, ".//tr[td[normalize-space()='Queue']]/td[2]")
        priority_cell = find(:xpath, ".//tr[td[normalize-space()='Priority']]/td[2]")

        expect(queue_cell).to have_text("critical")
        expect(priority_cell).to have_text("9")
      end
    end
  end

  context "when showing a failed execution with a serialized error payload" do
    before do
      ensure_solid_queue_tables!
      stub_solid_queue_models!
      SolidQueue::FailedExecution.serialize :error, coder: JSON
      SolidObserver.config.storage_mode = :persistence

      SolidQueue::ReadyExecution.delete_all
      SolidQueue::ScheduledExecution.delete_all
      SolidQueue::ClaimedExecution.delete_all
      SolidQueue::FailedExecution.delete_all
      SolidQueue::Job.delete_all

      now = Time.current
      failed_job = SolidQueue::Job.create!(
        queue_name: "default",
        class_name: "FailedHashErrorJob",
        priority: 0,
        created_at: now - 1.minute,
        updated_at: now - 1.minute
      )
      @failed_execution = SolidQueue::FailedExecution.create!(
        job: failed_job,
        error: {
          "exception_class" => "SolidQueue::Processes::ProcessExitError",
          "message" => "Process pid=8471 exited unexpectedly. Received unhandled signal 6.",
          "backtrace" => nil
        },
        created_at: now - 1.minute
      )
    end

    after do
      SolidQueue::ReadyExecution.delete_all if defined?(SolidQueue::ReadyExecution)
      SolidQueue::ScheduledExecution.delete_all if defined?(SolidQueue::ScheduledExecution)
      SolidQueue::ClaimedExecution.delete_all if defined?(SolidQueue::ClaimedExecution)
      SolidQueue::FailedExecution.delete_all if defined?(SolidQueue::FailedExecution)
      SolidQueue::Job.delete_all if defined?(SolidQueue::Job)
    end

    it "renders the error details from the Hash payload" do
      visit "/solid_observer/jobs/#{@failed_execution.id}?status=failed"

      expect(page.status_code).to eq(200)
      expect(page).to have_content("SolidQueue::Processes::ProcessExitError")
      expect(page).to have_content("Process pid=8471 exited unexpectedly")
      expect(page).to have_content("No backtrace available")
    end
  end
end
