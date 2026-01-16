# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "CreateSolidObserverStorageInfo migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/solid_observer_migrate/20260115000003_create_solid_observer_storage_info.rb")
  end

  let(:migration_class) { CreateSolidObserverStorageInfo }

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
    migration_class.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:solid_observer_storage_info)
  end

  describe "up migration" do
    it "creates solid_observer_storage_info table" do
      migration_class.migrate(:up)

      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_storage_info)).to be true
    end

    it "creates required columns with correct types" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_storage_info)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null}
      end

      expect(column_info["db_size_bytes"]).to include(type: :integer, null: false)
      expect(column_info["event_count"]).to include(type: :integer, null: false)
      expect(column_info["recorded_at"]).to include(type: :datetime, null: false)
    end

    it "creates index on recorded_at" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_storage_info)
      index_columns = indexes.map(&:columns).flatten

      expect(index_columns).to include("recorded_at")
    end

    it "allows inserting storage snapshots" do
      migration_class.migrate(:up)

      ActiveRecord::Base.connection.execute(
        "INSERT INTO solid_observer_storage_info (db_size_bytes, event_count, recorded_at) " \
        "VALUES (1048576, 1000, '2026-01-16 10:00:00')"
      )

      result = ActiveRecord::Base.connection.execute(
        "SELECT * FROM solid_observer_storage_info"
      ).first

      expect(result["db_size_bytes"]).to eq(1048576)
      expect(result["event_count"]).to eq(1000)
    end
  end

  describe "down migration" do
    it "removes solid_observer_storage_info table" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_storage_info)).to be true

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_storage_info)).to be false
    end
  end
end
