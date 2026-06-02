# frozen_string_literal: true

require "spec_helper"
require "active_record"

RSpec.describe "AddComponentToSolidObserverStorageInfos migration" do
  let(:migration_file) do
    File.join(__dir__, "../../../db/migrate/20260602000001_add_component_to_solid_observer_storage_infos.rb")
  end

  let(:migration_class) { AddComponentToSolidObserverStorageInfos }

  before(:all) do
    ActiveRecord::Base.establish_connection(adapter: "sqlite3", database: ":memory:")
  end

  before do
    ActiveRecord::Schema.define do
      create_table :solid_observer_storage_info, force: true do |t|
        t.bigint :db_size_bytes, null: false
        t.bigint :event_count, null: false
        t.datetime :recorded_at, null: false
      end
    end
    load migration_file
  end

  it "adds component column with default and index" do
    migration_class.migrate(:up)

    columns = ActiveRecord::Base.connection.columns(:solid_observer_storage_info)
    component = columns.find { |column| column.name == "component" }
    indexes = ActiveRecord::Base.connection.indexes(:solid_observer_storage_info)

    expect(component.null).to be(false)
    expect(component.default).to eq("queue_observer")
    expect(indexes.map(&:columns)).to include(["component"])
  end
end
