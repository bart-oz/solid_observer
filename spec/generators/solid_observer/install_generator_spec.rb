# frozen_string_literal: true

require "spec_helper"
require "generators/solid_observer/install_generator"
require "fileutils"
require "tmpdir"

RSpec.describe SolidObserver::Generators::InstallGenerator do
  let(:destination) { Dir.mktmpdir }

  before do
    FileUtils.mkdir_p(File.join(destination, "config"))
    FileUtils.mkdir_p(File.join(destination, "db"))

    File.write(
      File.join(destination, "config", "routes.rb"),
      <<~RUBY
        Rails.application.routes.draw do
        end
      RUBY
    )

    File.write(
      File.join(destination, "config", "database.yml"),
      <<~YAML
        default: &default
          adapter: sqlite3
          pool: 5
          timeout: 5000

        development:
          <<: *default
          database: storage/development.sqlite3

        test:
          <<: *default
          database: storage/test.sqlite3

        production:
          <<: *default
          database: storage/production.sqlite3
      YAML
    )

    allow(Rails).to receive(:root).and_return(Pathname.new(destination))
  end

  after do
    FileUtils.rm_rf(destination)
  end

  def run_generator
    generator = described_class.new([], {}, {destination_root: destination})
    generator.invoke_all
  end

  def capture_stdout
    original = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original
  end

  describe "initializer" do
    before { run_generator }

    it "creates initializer file" do
      expect(File).to exist(File.join(destination, "config/initializers/solid_observer.rb"))
    end

    it "contains configuration block" do
      initializer = File.read(File.join(destination, "config/initializers/solid_observer.rb"))
      expect(initializer).to include("SolidObserver.configure do |config|")
    end

    it "sets sensible defaults" do
      initializer = File.read(File.join(destination, "config/initializers/solid_observer.rb"))
      expect(initializer).to include("config.ui_enabled = !Rails.env.production?")
      expect(initializer).to include("config.observe_queue = true")
    end
  end

  describe "engine mount" do
    before { run_generator }

    it "mounts SolidObserver::Engine in routes.rb" do
      routes = File.read(File.join(destination, "config/routes.rb"))
      expect(routes).to include('mount SolidObserver::Engine, at: "/solid_observer"')
    end
  end

  describe "database configuration" do
    before { run_generator }

    it "injects queue database config into database.yml for each environment" do
      database_yml = File.read(File.join(destination, "config/database.yml"))
      expect(database_yml).to include("solid_observer_queue:")
      expect(database_yml).to include("storage/development_solid_observer_queue.sqlite3")
      expect(database_yml).to include("storage/test_solid_observer_queue.sqlite3")
      expect(database_yml).to include("storage/production_solid_observer_queue.sqlite3")
    end

    it "produces self-contained SQLite config without YAML merge from host default" do
      database_yml = File.read(File.join(destination, "config/database.yml"))
      observer_blocks = database_yml.scan(/solid_observer_queue:.*?(?=\n\S|\z)/m)
      expect(observer_blocks).not_to be_empty
      observer_blocks.each do |block|
        expect(block).not_to include("<<: *default")
        expect(block).to include("adapter: sqlite3")
        expect(block).to include("pool: 5")
        expect(block).to include("timeout: 5000")
        expect(block).to include("migrations_paths: db/solid_observer_migrate")
      end
    end
  end

  describe "post-install instructions" do
    it "warns non-SQLite host apps to review observer database config before db:create" do
      output = capture_stdout { run_generator }
      expect(output).to include("PostgreSQL or MySQL")
      expect(output).to include("review")
      expect(output).to include("db:create")
    end
  end
end
