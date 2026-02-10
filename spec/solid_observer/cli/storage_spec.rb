# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Storage do
  let(:storage_cli) { described_class.new }
  let(:temp_db_path) { File.join(Dir.tmpdir, "test_queue_#{Process.pid}.sqlite3") }

  before do
    allow(SolidObserver.config).to receive(:max_db_size).and_return(1.gigabyte)
    allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.8)
    allow(SolidObserver.config).to receive(:event_retention).and_return(30.days)

    db_config = double("db_config", database: temp_db_path)
    allow(SolidObserver::QueueEvent).to receive(:connection_db_config).and_return(db_config)
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

        capture_stdout { storage_cli.call }
      end
    end

    context "when database file exists" do
      before do
        FileUtils.mkdir_p(File.dirname(temp_db_path))
        File.write(temp_db_path, "x" * 10_485_760)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(45_231)
      end

      after do
        File.delete(temp_db_path) if File.exist?(temp_db_path)
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
        FileUtils.mkdir_p(File.dirname(temp_db_path))
        File.write(temp_db_path, "x" * 891_289_600)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100_000)
      end

      after do
        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end

      it "shows warning indicator" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("⚠️  Warning")
        expect(output).to include("83.01%")
      end

      it "displays size in GB when over 1024 MB" do
        File.write(temp_db_path, "x" * 1_610_612_736)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("GB")
      end
    end

    context "when database file does not exist" do
      before do
        File.delete(temp_db_path) if File.exist?(temp_db_path)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(0)
      end

      it "displays zero size gracefully" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("0.0 MB")
        expect(output).to include("0%")
        expect(output).to include("✓ OK")
      end
    end

    context "when there is an error gathering stats" do
      before do
        allow(SolidObserver::QueueEvent).to receive(:count).and_raise(StandardError.new("Connection failed"))
      end

      it "displays error message" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Failed to gather storage stats")
        expect(output).to include("Connection failed")
      end
    end

    context "when database size calculation fails" do
      before do
        allow(File).to receive(:exist?).and_return(true)
        allow(File).to receive(:size).and_raise(StandardError.new("Permission denied"))
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(1000)
      end

      it "displays warning and continues with zero size" do
        output = capture_stdout { storage_cli.call }

        expect(output).to include("Could not calculate database size")
        expect(output).to include("0.0 MB")
      end
    end

    context "with different retention periods" do
      it "displays 7 days retention" do
        allow(SolidObserver.config).to receive(:event_retention).and_return(7.days)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        File.write(temp_db_path, "x" * 1_048_576)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Retention: 7 days")

        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end

      it "displays 90 days retention" do
        allow(SolidObserver.config).to receive(:event_retention).and_return(90.days)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        File.write(temp_db_path, "x" * 1_048_576)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Retention: 90 days")

        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end
    end

    context "with different max_db_size configurations" do
      it "displays 500 MB max size" do
        allow(SolidObserver.config).to receive(:max_db_size).and_return(500.megabytes)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        File.write(temp_db_path, "x" * 1_048_576) # 1 MB

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Max size:  500.0 MB per database")

        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end

      it "displays 2 GB max size" do
        allow(SolidObserver.config).to receive(:max_db_size).and_return(2.gigabytes)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        File.write(temp_db_path, "x" * 1_048_576)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Max size:  2.0 GB per database")

        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end
    end

    context "with different warning thresholds" do
      it "shows warning at 90% threshold" do
        allow(SolidObserver.config).to receive(:warning_threshold).and_return(0.9)
        allow(SolidObserver::QueueEvent).to receive(:count).and_return(100)
        File.write(temp_db_path, "x" * 943_718_400)

        output = capture_stdout { storage_cli.call }

        expect(output).to include("Warning:   90% threshold")
        expect(output).to include("✓ OK")

        File.delete(temp_db_path) if File.exist?(temp_db_path)
      end
    end

    context "number formatting" do
      before do
        File.write(temp_db_path, "x" * 1_048_576)
      end

      after do
        File.delete(temp_db_path) if File.exist?(temp_db_path)
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
