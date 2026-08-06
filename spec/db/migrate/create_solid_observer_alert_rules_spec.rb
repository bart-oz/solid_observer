# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "CreateSolidObserverAlertRules migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/migrate/20260804000001_create_solid_observer_alert_rules.rb")
  end

  let(:migration_class) { CreateSolidObserverAlertRules }

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
    migration_class.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_rules)
  end

  describe "up migration" do
    it "creates solid_observer_alert_rules table" do
      migration_class.migrate(:up)

      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_rules)).to be true
    end

    it "creates required columns with correct types" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_alert_rules)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null, limit: col.limit}
      end

      expect(column_info["rule_name"]).to include(type: :string, null: false, limit: 120)
      expect(column_info["metric_type"]).to include(type: :string, null: false, limit: 50)
      expect(column_info["threshold_value"]).to include(type: :float, null: false)
      expect(column_info["comparison_operator"]).to include(type: :string, null: false, limit: 3)
      expect(column_info["cooldown_minutes"]).to include(type: :integer, null: false)
      expect(column_info["enabled"]).to include(type: :boolean, null: false)
    end

    it "applies database defaults for cooldown_minutes and enabled" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_alert_rules " \
          "(rule_name, metric_type, threshold_value, comparison_operator, created_at, updated_at) " \
          "VALUES ('defaults-rule', 'queue_latency', 100.0, '>', '2026-08-04 10:00:00', '2026-08-04 10:00:00')"
      )

      row = ActiveRecord::Base.connection.select_one(
        "SELECT cooldown_minutes, enabled FROM solid_observer_alert_rules WHERE rule_name = 'defaults-rule'"
      )

      expect(row["cooldown_minutes"]).to eq(15)
      expect(row["enabled"]).to be_truthy
    end

    it "creates indexes on rule_name, enabled, and metric_type" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_alert_rules)
      index_columns = indexes.map(&:columns).flatten
      index_names = indexes.map(&:name)
      eval_index = indexes.find { |idx| idx.name == "idx_solid_observer_alert_rules_eval" }

      expect(index_names).to include(
        "idx_solid_observer_alert_rules_name_unique",
        "idx_solid_observer_alert_rules_eval"
      )
      expect(eval_index).not_to be_nil
      expect(eval_index.columns).to eq(["metric_type", "enabled"])
      expect(index_columns).to include("enabled")
    end

    it "enforces unique rule_name at the database level" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_alert_rules " \
          "(rule_name, metric_type, threshold_value, comparison_operator, cooldown_minutes, enabled, created_at, updated_at) " \
          "VALUES ('queue-latency', 'queue_latency', 100.0, '>', 15, 1, '2026-08-04 10:00:00', '2026-08-04 10:00:00')"
      )

      expect {
        ActiveRecord::Base.connection.execute(
          "INSERT INTO solid_observer_alert_rules " \
            "(rule_name, metric_type, threshold_value, comparison_operator, cooldown_minutes, enabled, created_at, updated_at) " \
            "VALUES ('queue-latency', 'queue_latency', 200.0, '>', 15, 1, '2026-08-04 11:00:00', '2026-08-04 11:00:00')"
        )
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe "down migration" do
    it "removes solid_observer_alert_rules table" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_rules)).to be true

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_alert_rules)).to be false
    end
  end
end
