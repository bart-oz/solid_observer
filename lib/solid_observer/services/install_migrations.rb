# frozen_string_literal: true

module SolidObserver
  module Services
    class InstallMigrations
      def self.call(rails_env: Rails.env)
        new(rails_env).call
      end

      def initialize(rails_env)
        @rails_env = rails_env
      end

      def call
        destination = resolve_destination
        copied = ActiveRecord::Migration.copy(
          destination,
          "solid_observer" => SolidObserver::Engine.paths["db/migrate"].existent.first
        )

        {
          destination: destination,
          copied: copied
        }
      end

      private

      def resolve_destination
        path = configured_path
        return path if path

        ActiveRecord::Tasks::DatabaseTasks.migrations_paths.first || "db/migrate"
      end

      def configured_path
        config = ActiveRecord::Base.configurations.configs_for(
          env_name: @rails_env,
          name: "solid_observer_queue"
        )
        path = Array(config&.migrations_paths).first
        return if path.blank?

        FileUtils.mkdir_p(path) unless Dir.exist?(path)
        path
      end
    end
  end
end
