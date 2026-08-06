# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "CreateSolidObserverAlertHistories migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/migrate/20260804000002_create_solid_observer_alert_histories.rb")
  end

  let(:migration_class) { CreateSolidObserverAlertHistories }

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
    migration_class.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_histories)
  end

  describe "up migration" do
    it "creates solid_observer_alert_histories table" do
      migration_class.migrate(:up)

      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_histories)).to be true
    end

    it "creates required columns with correct types" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_alert_histories)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null, limit: col.limit}
      end

      expect(column_info["alert_rule_id"]).to include(type: :integer, null: false)
      expect(column_info["triggered_at"]).to include(type: :datetime, null: false)
      expect(column_info["resolved_at"]).to include(type: :datetime, null: true)
      expect(column_info["metric_value"]).to include(type: :float, null: false)
      expect(column_info["state"]).to include(type: :string, null: false, limit: 16)
      expect(column_info["payload"]).to include(type: :text)
      expect(column_info["created_at"]).to include(type: :datetime, null: false)
      expect(column_info["updated_at"]).to include(type: :datetime, null: false)
    end

    it "creates indexes on alert_rule_id, triggered_at, and state" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_alert_histories)
      index_columns = indexes.map(&:columns).flatten
      alert_rule_index = indexes.find { |idx| idx.name == "idx_solid_observer_alert_histories_rule" }

      expect(alert_rule_index).not_to be_nil
      expect(alert_rule_index.columns).to eq(["alert_rule_id"])
      expect(index_columns).to include("triggered_at")
      expect(index_columns).to include("state")
    end

    it "creates the partial unique index for active rows" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_alert_histories)
      active_index = indexes.find { |idx| idx.name == "idx_solid_observer_alert_histories_active_unique" }

      expect(active_index).not_to be_nil
      expect(active_index.columns).to eq(["alert_rule_id"])
      expect(active_index.unique).to be true
      expect(active_index.where).to eq("state = 'triggered'")
    end

    it "prevents duplicate active rows for the same rule" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_alert_histories " \
          "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
          "VALUES (1, '2026-08-04 10:00:00', 42.0, 'triggered', " \
          "'2026-08-04 10:00:00', '2026-08-04 10:00:00')"
      )

      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_alert_histories " \
            "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
            "VALUES (1, '2026-08-04 10:05:00', 43.0, 'triggered', " \
            "'2026-08-04 10:05:00', '2026-08-04 10:05:00')"
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end

    it "allows resolved rows and active rows for different rules" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_alert_histories " \
          "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
          "VALUES (1, '2026-08-04 10:00:00', 42.0, 'triggered', " \
          "'2026-08-04 10:00:00', '2026-08-04 10:00:00')"
      )

      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_alert_histories " \
            "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
            "VALUES (1, '2026-08-04 10:05:00', 43.0, 'resolved', " \
            "'2026-08-04 10:05:00', '2026-08-04 10:05:00')"
        )
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_alert_histories " \
            "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
            "VALUES (1, '2026-08-04 10:10:00', 44.0, 'resolved', " \
            "'2026-08-04 10:10:00', '2026-08-04 10:10:00')"
        )
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_alert_histories " \
            "(alert_rule_id, triggered_at, metric_value, state, created_at, updated_at) " \
            "VALUES (2, '2026-08-04 10:15:00', 45.0, 'triggered', " \
            "'2026-08-04 10:15:00', '2026-08-04 10:15:00')"
        )
      }.not_to raise_error
    end
  end

  describe "down migration" do
    it "removes solid_observer_alert_histories table" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_histories)).to be true

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_histories)).to be false
    end
  end
end
