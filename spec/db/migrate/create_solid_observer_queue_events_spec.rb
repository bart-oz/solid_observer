# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "CreateSolidObserverQueueEvents migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/solid_observer_migrate/20260115000001_create_solid_observer_queue_events.rb")
  end

  let(:migration_class) { CreateSolidObserverQueueEvents }

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
    migration_class.migrate(:down) if ActiveRecord::Base.connection.table_exists?(:solid_observer_queue_events)
  end

  describe "up migration" do
    it "creates solid_observer_queue_events table" do
      migration_class.migrate(:up)

      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_queue_events)).to be true
    end

    it "creates required columns with correct types" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_queue_events)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null, limit: col.limit}
      end

      expect(column_info["event_type"]).to include(type: :string, null: false, limit: 50)
      expect(column_info["correlation_id"]).to include(type: :string, limit: 64)
      expect(column_info["metadata"]).to include(type: :text)
      expect(column_info["duration"]).to include(type: :float)
      expect(column_info["recorded_at"]).to include(type: :datetime, null: false)
    end

    it "creates indexes on recorded_at, correlation_id, and event_type" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_queue_events)
      index_columns = indexes.map(&:columns).flatten

      expect(index_columns).to include("recorded_at")
      expect(index_columns).to include("correlation_id")
      expect(index_columns).to include("event_type")
    end

    it "creates partial index on correlation_id" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_queue_events)
      correlation_id_index = indexes.find { |idx| idx.columns == ["correlation_id"] }

      expect(correlation_id_index).not_to be_nil
      expect(correlation_id_index.where).to eq("correlation_id IS NOT NULL")
    end
  end

  describe "down migration" do
    it "removes solid_observer_queue_events table" do
      migration_class.migrate(:up)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_queue_events)).to be true

      migration_class.migrate(:down)
      expect(ActiveRecord::Base.connection.table_exists?(:solid_observer_queue_events)).to be false
    end
  end
end
