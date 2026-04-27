# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Status do
  let(:status) { described_class.new }

  describe "#call" do
    context "when SolidQueue is available" do
      let(:stats) do
        {
          ready: 10,
          scheduled: 5,
          claimed: 3,
          failed: 2,
          workers: 4,
          queues: {"default" => 8, "mailers" => 2},
          available: true
        }
      end

      before do
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
      end

      it "displays header" do
        expect { status.call }.to output(/📊 SolidObserver Status/).to_stdout
      end

      it "prints the indented banner icon with name beside the middle row, above the header" do
        output = capture_stdout { status.call }

        expect(output).to include("         ┌─   ─┐")
        expect(output).to include("            ◉")
        expect(output).to include("         └─   ─┘")
        expect(output).to include("solid_observer")

        icon_idx = output.index("         ┌─   ─┐")
        header_idx = output.index("📊 SolidObserver Status")
        expect(icon_idx).to be < header_idx
      end

      it "displays queue statistics table" do
        output = capture_stdout { status.call }

        expect(output).to include("🚀 Solid Queue")
        expect(output).to include("Metric")
        expect(output).to include("Value")
        expect(output).to include("Ready")
        expect(output).to include("10")
        expect(output).to include("Scheduled")
        expect(output).to include("5")
        expect(output).to include("Claimed")
        expect(output).to include("3")
        expect(output).to include("Failed")
        expect(output).to include("2")
        expect(output).to include("Workers")
        expect(output).to include("4")
      end

      it "displays queue depths table" do
        output = capture_stdout { status.call }

        expect(output).to include("📋 Queue Depths")
        expect(output).to include("Queue")
        expect(output).to include("Jobs")
        expect(output).to include("default")
        expect(output).to include("8")
        expect(output).to include("mailers")
        expect(output).to include("2")
      end

      it "sorts queues alphabetically" do
        stats[:queues] = {"zebra" => 1, "alpha" => 2, "beta" => 3}
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)

        output = capture_stdout { status.call }

        alpha_index = output.index("alpha")
        beta_index = output.index("beta")
        zebra_index = output.index("zebra")

        expect(alpha_index).to be < beta_index
        expect(beta_index).to be < zebra_index
      end

      context "when no queues have jobs" do
        before do
          stats[:queues] = {}
          allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
        end

        it "does not display queue depths section" do
          output = capture_stdout { status.call }

          expect(output).not_to include("📋 Queue Depths")
        end
      end
    end

    context "when SolidQueue is not available" do
      let(:stats) do
        {
          ready: 0,
          scheduled: 0,
          claimed: 0,
          failed: 0,
          workers: 0,
          queues: {},
          available: false,
          error: "SolidQueue not available"
        }
      end

      before do
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
      end

      it "displays header" do
        expect { status.call }.to output(/📊 SolidObserver Status/).to_stdout
      end

      it "displays warning message" do
        output = capture_stdout { status.call }

        expect(output).to include("⚠️  SolidQueue not available")
        expect(output).to include("SolidQueue not available")
      end

      it "does not display queue statistics table" do
        output = capture_stdout { status.call }

        expect(output).not_to include("🚀 Solid Queue")
        expect(output).not_to include("Metric")
      end

      it "does not display queue depths table" do
        output = capture_stdout { status.call }

        expect(output).not_to include("📋 Queue Depths")
      end
    end

    context "when database error occurs" do
      let(:stats) do
        {
          ready: 0,
          scheduled: 0,
          claimed: 0,
          failed: 0,
          workers: 0,
          queues: {},
          available: false,
          error: "Database connection failed"
        }
      end

      before do
        allow(SolidObserver::QueueStats).to receive(:snapshot).and_return(stats)
      end

      it "displays error message" do
        output = capture_stdout { status.call }

        expect(output).to include("⚠️  SolidQueue not available")
        expect(output).to include("Database connection failed")
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
