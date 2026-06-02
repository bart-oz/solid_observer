# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Storage do
  let(:storage_cli) { described_class.new }

  before do
    allow(SolidObserver.config).to receive(:max_db_size).and_return(1.gigabyte)
    allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.8)
    allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)
  end

  after { SolidObserver.reset_configuration! }

  describe "#call" do
    context "when in realtime mode" do
      before { SolidObserver.config.storage_mode = :realtime }

      it "displays informative message" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("not available in real-time mode")
      end
    end

    context "when component snapshots are available" do
      before do
        allow(SolidObserver::Services::StorageInfoSnapshot).to receive(:call).and_return([
          {label: "Queue observer", available: true, db_size_bytes: 10_485_760, event_count: 45_231},
          {label: "Cache observer", available: true, db_size_bytes: 5_242_880, event_count: 12_000},
          {label: "SolidCache", available: false, db_size_bytes: nil, event_count: nil}
        ])
      end

      it "prints all components and statuses" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Queue observer")
        expect(output).to include("Cache observer")
        expect(output).to include("SolidCache")
        expect(output).to include("10.0 MB")
        expect(output).to include("45,231")
        expect(output).to include("— Unavailable")
      end
    end
  end

  private

  def capture_stdout
    original_stdout = $stdout
    $stdout = StringIO.new
    yield
    $stdout.string
  ensure
    $stdout = original_stdout
  end
end
