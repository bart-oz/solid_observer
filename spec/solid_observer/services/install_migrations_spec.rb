# frozen_string_literal: true

require "spec_helper"
require_relative "../../../lib/solid_observer/services/install_migrations"

RSpec.describe SolidObserver::Services::InstallMigrations do
  let(:configurations) { instance_double(ActiveRecord::DatabaseConfigurations) }
  let(:source_paths) { double("source_paths", existent: ["/gem/solid_observer/db/migrate"]) }
  let(:migration_class) do
    Class.new do
      def self.copy(*)
      end
    end
  end

  before do
    stub_const("ActiveRecord::Migration", migration_class)
    allow(ActiveRecord::Base).to receive(:configurations).and_return(configurations)
    allow(SolidObserver::Engine.paths).to receive(:[]).with("db/migrate").and_return(source_paths)
  end

  describe ".call" do
    context "when solid_observer_queue config has migrations_paths" do
      let(:db_config) { double("db_config", migrations_paths: "db/solid_observer_migrate") }

      before do
        allow(configurations).to receive(:configs_for)
          .with(env_name: "test", name: "solid_observer_queue")
          .and_return(db_config)
        allow(Dir).to receive(:exist?).with("db/solid_observer_migrate").and_return(false)
        allow(FileUtils).to receive(:mkdir_p)
        allow(ActiveRecord::Migration).to receive(:copy).and_return(["20260115000001"])
      end

      it "copies migrations to the configured destination" do
        result = described_class.call(rails_env: "test")

        expect(ActiveRecord::Migration).to have_received(:copy).with(
          "db/solid_observer_migrate",
          "solid_observer" => "/gem/solid_observer/db/migrate"
        )
        expect(result).to eq(
          destination: "db/solid_observer_migrate",
          copied: ["20260115000001"]
        )
      end

      it "creates the destination directory when missing" do
        described_class.call(rails_env: "test")

        expect(FileUtils).to have_received(:mkdir_p).with("db/solid_observer_migrate")
      end
    end

    context "when solid_observer_queue config has no migrations_paths" do
      let(:db_config) { double("db_config", migrations_paths: nil) }

      before do
        allow(configurations).to receive(:configs_for)
          .with(env_name: "test", name: "solid_observer_queue")
          .and_return(db_config)
        allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:migrations_paths).and_return(["db/default_migrate"])
        allow(ActiveRecord::Migration).to receive(:copy).and_return([])
      end

      it "falls back to ActiveRecord::Tasks::DatabaseTasks.migrations_paths.first" do
        result = described_class.call(rails_env: "test")

        expect(ActiveRecord::Migration).to have_received(:copy).with(
          "db/default_migrate",
          "solid_observer" => "/gem/solid_observer/db/migrate"
        )
        expect(result).to eq(
          destination: "db/default_migrate",
          copied: []
        )
      end
    end

    context "when solid_observer_queue config is absent" do
      before do
        allow(configurations).to receive(:configs_for)
          .with(env_name: "test", name: "solid_observer_queue")
          .and_return(nil)
        allow(ActiveRecord::Tasks::DatabaseTasks).to receive(:migrations_paths).and_return(["db/fallback_migrate"])
        allow(ActiveRecord::Migration).to receive(:copy).and_return(["20260115000001", "20260115000002"])
      end

      it "uses the default Rails migrations path fallback" do
        result = described_class.call(rails_env: "test")

        expect(ActiveRecord::Migration).to have_received(:copy).with(
          "db/fallback_migrate",
          "solid_observer" => "/gem/solid_observer/db/migrate"
        )
        expect(result).to eq(
          destination: "db/fallback_migrate",
          copied: ["20260115000001", "20260115000002"]
        )
      end
    end
  end
end
