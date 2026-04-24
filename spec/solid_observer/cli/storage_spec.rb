# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Storage do
  let(:storage_cli) { described_class.new }
  let(:connection) { instance_double(ActiveRecord::ConnectionAdapters::AbstractAdapter) }

  before do
    allow(SolidObserver.config).to receive(:max_db_size).and_return(1.gigabyte)
    allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.8)
    allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)
    allow(SolidObserver::QueueEvent).to receive(:connection).and_return(connection)
  end

  after { SolidObserver.reset_configuration! }

  describe "#call" do
    context "when in realtime mode" do
      before do
        SolidObserver.config.storage_mode = :realtime
      end

      it "displays informative message" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("💾 Storage Status")
        expect(output).to include("not available in real-time mode")
        expect(output).to include("persistence mode")
      end

      it "does not query the database" do
        expect(SolidObserver::QueueEvent).not_to receive(:count)
        expect(SolidObserver::Services::DatabaseSize).not_to receive(:call)

        capture_stdout { storage_cli.call }
      end
    end

    context "when database size is available" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(10_485_760)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(45_231)
      end

      it "displays storage status with correct calculations" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("💾 Storage Status")
        expect(output).to include("Component")
        expect(output).to include("Size")
        expect(output).to include("Events")
        expect(output).to include("Usage")
        expect(output).to include("Status")
        expect(output).to include("Queue")
        expect(output).to include("10.0 MB")
        expect(output).to include("45,231")
        expect(output).to include("✓ OK")
      end

      it "displays configuration information" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Configuration:")
        expect(output).to include("Retention: 30 days")
        expect(output).to include("Max size:  1.0 GB per database")
        expect(output).to include("Warning:   80% threshold")
      end

      it "calculates percentage correctly" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("0.98%")
      end
    end

    context "when database size exceeds warning threshold" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(891_289_600)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100_000)
      end

      it "shows warning indicator" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("⚠️  Warning")
        expect(output).to include("83.01%")
      end

      it "displays size in GB when over 1024 MB" do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_610_612_736)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("GB")
      end
    end

    context "when DatabaseSize returns nil" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(nil)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(1_000)
      end

      it "displays unknown storage values as N/A" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("N/A")
        expect(output.scan("N/A").length).to be >= 2
        expect(output).to include("— Unknown")
      end
    end

    context "when there is an error gathering stats" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(10_485_760)
        allow(SolidObserver::QueueEvent).to receive(:count).and_raise(StandardError.new("Connection failed"))
      end

      it "displays error message" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Failed to gather storage stats")
        expect(output).to include("Connection failed")
      end
    end

    context "when DatabaseSize raises an unexpected error" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_raise(StandardError.new("Permission denied"))
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(1000)
      end

      it "displays error message" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Failed to gather storage stats")
        expect(output).to include("Permission denied")
      end
    end

    context "with different retention periods" do
      it "displays 7 days retention" do
        allow(SolidObserver.config).to receive(:event_retention).and_return(7.days)
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_048_576)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Retention: 7 days")
      end

      it "displays 90 days retention" do
        allow(SolidObserver.config).to receive(:event_retention).and_return(90.days)
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_048_576)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Retention: 90 days")
      end
    end

    context "with different max_db_size configurations" do
      it "displays 500 MB max size" do
        allow(SolidObserver.config).to receive(:max_db_size).and_return(500.megabytes)
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_048_576)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Max size:  500.0 MB per database")
      end

      it "displays 2 GB max size" do
        allow(SolidObserver.config).to receive(:max_db_size).and_return(2.gigabytes)
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_048_576)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Max size:  2.0 GB per database")
      end
    end

    context "with different warning thresholds" do
      it "shows warning at 90% threshold" do
        allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.9)
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(943_718_400)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Warning:   90% threshold")
        expect(output).to include("✓ OK")
      end
    end

    context "number formatting" do
      before do
        allow(SolidObserver::Services::DatabaseSize).to receive(:call).with(connection: connection).and_return(1_048_576)
      end

      it "formats small numbers without commas" do
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(999)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("999")
      end

      it "formats thousands with commas" do
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(1_234)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("1,234")
      end

      it "formats millions with commas" do
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(1_234_567)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("1,234,567")
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
