# frozen_string_literal: true

namespace :solid_observer do
  desc "Display SolidObserver status with queue statistics"
  task status: :environment do
    SolidObserver::CLI::Status.call
  end
end
