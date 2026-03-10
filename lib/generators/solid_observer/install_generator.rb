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
        %w[development test production].each do |env|
          config_block = <<-YAML
  solid_observer_queue:
    <<: *default
    database: storage/#{env}_solid_observer_queue.sqlite3
          YAML
          inject_into_file "config/database.yml", config_block, after: /^#{env}:\n(?:  .*\n)*/
        end
      end

      def add_engine_mount
        route 'mount SolidObserver::Engine, at: "/solid_observer"'
      end

      def show_instructions
        say "\n"
        print_banner
        say "\n"
        say "Next steps:", :yellow
        say "  1. Review configuration in config/initializers/solid_observer.rb"
        say "  2. Install migrations: bin/rails solid_observer:install:migrations"
        say "  3. Create database: bin/rails db:create"
        say "  4. Run migrations: bin/rails db:migrate"
        say "  5. Restart your Rails server"
        say "  6. Visit /solid_observer to access the web dashboard"
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
