# frozen_string_literal: true

require "rails/generators"

module SolidObserver
  module Generators
    class InstallGenerator < Rails::Generators::Base
      source_root File.expand_path("templates", __dir__)

      desc "Install SolidObserver with initializer and database configuration"

      def create_initializer
        template "initializer.rb.tt", "config/initializers/solid_observer.rb"
      end

      def add_database_configuration
        database_config = <<~YAML

          solid_observer_queue:
            <<: *default
            database: storage/<%= Rails.env %>_solid_observer_queue.sqlite3
            migrations_paths: db/solid_observer_migrate
        YAML

        inject_into_file "config/database.yml", database_config, after: /^default:.*$\n(?:  .*\n)*/
      end

      def create_migration_directory
        empty_directory "db/solid_observer_migrate"
      end

      def show_instructions
        say "\n"
        print_banner
        say "\n"
        say "Next steps:", :yellow
        say "  1. Review configuration in config/initializers/solid_observer.rb"
        say "  2. Install migrations: rails solid_observer:install:migrations"
        say "  3. Create database: rails db:create:solid_observer_queue"
        say "  4. Run migrations: rails db:migrate"
        say "  5. Restart your Rails server"
        say "\n"
        say "Documentation: https://solid.observer", :cyan
        say "GitHub: https://github.com/bart-oz/solid_observer", :cyan
        say "\n"
      end

      private

      def print_banner
        banner = <<~BANNER

          ███████╗ ██████╗ ██╗     ██╗██████╗
          ██╔════╝██╔═══██╗██║     ██║██╔══██╗
          ███████╗██║   ██║██║     ██║██║  ██║
          ╚════██║██║   ██║██║     ██║██║  ██║
          ███████║╚██████╔╝███████╗██║██████╔╝
          ╚══════╝ ╚═════╝ ╚══════╝╚═╝╚═════╝

           ██████╗ ██████╗ ███████╗███████╗██████╗ ██╗   ██╗███████╗██████╗
          ██╔═══██╗██╔══██╗██╔════╝██╔════╝██╔══██╗██║   ██║██╔════╝██╔══██╗
          ██║   ██║██████╔╝███████╗█████╗  ██████╔╝██║   ██║█████╗  ██████╔╝
          ██║   ██║██╔══██╗╚════██║██╔══╝  ██╔══██╗╚██╗ ██╔╝██╔══╝  ██╔══██╗
          ╚██████╔╝██████╔╝███████║███████╗██║  ██║ ╚████╔╝ ███████╗██║  ██║
           ╚═════╝ ╚═════╝ ╚══════╝╚══════╝╚═╝  ╚═╝  ╚═══╝  ╚══════╝╚═╝  ╚═╝

                 Observe your Solid Stack like a pro! 🔭
                                v#{SolidObserver::VERSION}

        BANNER

        banner.each_line { |line| say line.chomp, :cyan }
        say "  ✓ SolidObserver installed successfully!", :green
      end
    end
  end
end
