# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "CreateSolidObserverMetrics migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/solid_observer_migrate/20260115000002_create_solid_observer_metrics.rb")
  end

  let(:migration_class) { CreateSolidObserverMetrics }

  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end

  before do
    load migration_file
  end

  after do
    migration_class.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:solid_observer_metrics)
  end

  describe "up migration" do
    it "creates solid_observer_metrics table" do
      migration_class.migrate(:up)

      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_metrics)).to be true
    end

    it "creates required columns with correct types" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_metrics)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null, limit: col.limit, default: col.default}
      end

      expect(column_info["metric_name"]).to include(type: :string, null: false, limit: 50)
      expect(column_info["value"]).to include(type: :integer, null: false)
      expect(column_info["value"][:default].to_i).to eq(0) # Rails 8.0 returns "0" as string
      expect(column_info["period_start"]).to include(type: :datetime, null: false)
      expect(column_info["period_type"]).to include(type: :string, null: false, limit: 10)
    end

    it "creates unique composite index on metric_name, period_start, and period_type" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_metrics)
      unique_index = indexes.find { |idx| idx.name == "idx_solid_observer_metrics_unique" }

      expect(unique_index).not_to be_nil
      expect(unique_index.columns).to eq(["metric_name", "period_start", "period_type"])
      expect(unique_index.unique).to be true
    end

    it "prevents duplicate metric entries with unique index" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_metrics (metric_name, value, period_start, period_type) " \
        "VALUES ('jobs_enqueued', 100, '2026-01-15 10:00:00', 'hour')"
      )

      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_metrics (metric_name, value, period_start, period_type) " \
          "VALUES ('jobs_enqueued', 200, '2026-01-15 10:00:00', 'hour')"
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "down migration" do
    it "removes solid_observer_metrics table" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_metrics)).to be true

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_metrics)).to be false
    end
  end
end
