# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "AddCorrelationIdToCableEvents migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/migrate/20260630000002_add_correlation_id_to_cable_events.rb")
  end

  let(:migration_class) { AddCorrelationIdToCableEvents }

  before(:all) do
    ActiveRecord::Base.establish_connection(
      adapter: "sqlite3",
      database: ":memory:"
    )
  end

  before do
    load migration_file

    connection = ActiveRecord::Base.connection
    connection.create_table :solid_observer_cable_events do |t|
      t.string :event_type, null: false
      t.datetime :recorded_at, null: false
    end
  end

  after do
    connection = ActiveRecord::Base.connection
    connection.drop_table(:solid_observer_cable_events) if connection.table_exists?(:solid_observer_cable_events)
  end

  describe "up migration" do
    it "adds correlation_id column with limit 64" do
      migration_class.migrate(:up)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_cable_events)
      column_info = columns.each_with_object({}) do |col, hash|
        hash[col.name] = {type: col.type, null: col.null, limit: col.limit}
      end

      expect(column_info["correlation_id"]).to include(type: :string, limit: 64)
    end

    it "creates partial index on correlation_id" do
      migration_class.migrate(:up)

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_cable_events)
      correlation_id_index = indexes.find { |idx| idx.columns == ["correlation_id"] }

      expect(correlation_id_index).not_to be_nil
      expect(correlation_id_index.where).to eq("correlation_id IS NOT NULL")
    end
  end

  describe "down migration" do
    it "removes correlation_id column and index" do
      migration_class.migrate(:up)
      migration_class.migrate(:down)

      columns = ActiveRecord::Base.connection.columns(:solid_observer_cable_events).map(&:name)
      expect(columns).not_to include("correlation_id")

      indexes = ActiveRecord::Base.connection.indexes(:solid_observer_cable_events)
      expect(indexes.map(&:columns).flatten).not_to include("correlation_id")
    end
  end
end
