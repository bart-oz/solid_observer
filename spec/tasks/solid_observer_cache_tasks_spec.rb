# frozen_string_literal: true

require "spec_helper"

RSpec.describe "solid_observer cache rake tasks" do
  let(:task_source) do
    File.read(File.expand_path("../../lib/tasks/solid_observer.rake", __dir__))
  end

  it "defines the cache clear task with confirmation" do
    expect(task_source).to include("namespace :cache do")
    expect(task_source).to include("task clear: :environment do")
    expect(task_source).to include("SolidObserver::Services::CacheOperations.message(:clear, :confirmation)")
    expect(task_source).to include('puts "Aborted"')
  end

  it "defines the cache prune task" do
    expect(task_source).to include("task prune: :environment do")
    expect(task_source).to include("puts SolidObserver::Services::CacheOperations.prune[:message]")
  end

  it "uses the shared unavailable message guard for both cache tasks" do
    expect(task_source.scan("SolidObserver::Services::CacheOperations.unavailable_message").size).to eq(2)
  end
end
