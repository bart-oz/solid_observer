# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Base do
  let(:test_cli_class) do
    Class.new(described_class) do
      def call
        "executed"
      end
    end
  end

  let(:cli) { test_cli_class.new }

  describe ".call" do
    it "creates an instance and calls #call" do
      expect_any_instance_of(test_cli_class).to receive(:call)
      test_cli_class.call
    end
  end

  describe "#call" do
    it "raises NotImplementedError in base class" do
      base_cli = described_class.new
      expect { base_cli.call }.to raise_error(NotImplementedError, /must implement #call/)
    end
  end

  describe "#output" do
    it "outputs plain text without color" do
      expect { cli.send(:output, "Hello") }.to output("Hello\n").to_stdout
    end

    it "outputs colored text when color is enabled" do
      allow(cli).to receive(:color_enabled?).and_return(true)
      expect { cli.send(:output, "Hello", color: :red) }.to output("\e[31mHello\e[0m\n").to_stdout
    end

    it "skips color when color is disabled" do
      allow(cli).to receive(:color_enabled?).and_return(false)
      expect { cli.send(:output, "Hello", color: :red) }.to output("Hello\n").to_stdout
    end
  end

  describe "#error" do
    it "outputs text in red" do
      allow(cli).to receive(:color_enabled?).and_return(true)
      expect { cli.send(:error, "Error message") }.to output("\e[31mError message\e[0m\n").to_stdout
    end
  end

  describe "#success" do
    it "outputs text in green" do
      allow(cli).to receive(:color_enabled?).and_return(true)
      expect { cli.send(:success, "Success message") }.to output("\e[32mSuccess message\e[0m\n").to_stdout
    end
  end

  describe "#warning" do
    it "outputs text in yellow" do
      allow(cli).to receive(:color_enabled?).and_return(true)
      expect { cli.send(:warning, "Warning message") }.to output("\e[33mWarning message\e[0m\n").to_stdout
    end
  end

  describe "#info" do
    it "outputs text in blue" do
      allow(cli).to receive(:color_enabled?).and_return(true)
      expect { cli.send(:info, "Info message") }.to output("\e[34mInfo message\e[0m\n").to_stdout
    end
  end

  describe "#table" do
    let(:headers) { ["Name", "Age", "City"] }
    let(:rows) do
      [
        ["Alice", "30", "New York"],
        ["Bob", "25", "San Francisco"],
        ["Charlie", "35", "Los Angeles"]
      ]
    end

    it "outputs formatted table with headers and rows" do
      expect do
        cli.send(:table, headers: headers, rows: rows)
      end.to output(a_string_matching(/Name\s+Age\s+City/) && a_string_matching(/Alice\s+30\s+New York/)).to_stdout
    end

    it "does not output anything for empty rows" do
      expect { cli.send(:table, headers: headers, rows: []) }.not_to output.to_stdout
    end

    it "handles numeric values" do
      numeric_headers = ["ID", "Score"]
      numeric_rows = [[1, 100], [2, 95], [3, 88]]

      expect do
        cli.send(:table, headers: numeric_headers, rows: numeric_rows)
      end.to output(a_string_matching(/ID\s+Score/) && a_string_matching(/1\s+100/) && a_string_matching(/2\s+95/)).to_stdout
    end
  end

  describe "#confirm" do
    it "returns true for 'y' input" do
      allow($stdin).to receive(:gets).and_return("y\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?")).to be true
    end

    it "returns true for 'yes' input" do
      allow($stdin).to receive(:gets).and_return("yes\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?")).to be true
    end

    it "returns false for 'n' input" do
      allow($stdin).to receive(:gets).and_return("n\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?")).to be false
    end

    it "returns false for 'no' input" do
      allow($stdin).to receive(:gets).and_return("no\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?")).to be false
    end

    it "returns default value for empty input (default: true)" do
      allow($stdin).to receive(:gets).and_return("\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?", default: true)).to be true
    end

    it "returns default value for empty input (default: false)" do
      allow($stdin).to receive(:gets).and_return("\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?", default: false)).to be false
    end

    it "returns default value when stdin returns nil" do
      allow($stdin).to receive(:gets).and_return(nil)
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?", default: true)).to be true
    end

    it "is case insensitive" do
      allow($stdin).to receive(:gets).and_return("Y\n")
      allow(cli).to receive(:print)
      expect(cli.send(:confirm, "Continue?")).to be true
    end
  end

  describe "#color_enabled?" do
    it "returns true when stdout is a TTY" do
      allow($stdout).to receive(:tty?).and_return(true)
      expect(cli.send(:color_enabled?)).to be true
    end

    it "returns false when stdout is not a TTY" do
      allow($stdout).to receive(:tty?).and_return(false)
      expect(cli.send(:color_enabled?)).to be false
    end
  end

  describe "#colorize" do
    it "adds ANSI color codes" do
      expect(cli.send(:colorize, "text", :red)).to eq("\e[31mtext\e[0m")
    end

    it "returns original text for unknown color" do
      expect(cli.send(:colorize, "text", :unknown)).to eq("text")
    end

    it "returns original text when color is nil" do
      expect(cli.send(:colorize, "text", nil)).to eq("text")
    end
  end

  describe "#calculate_column_widths" do
    it "calculates correct widths for each column" do
      headers = ["Name", "Age"]
      rows = [["Alice", "30"], ["Bob", "5"]]

      widths = cli.send(:calculate_column_widths, headers, rows)
      expect(widths).to eq([5, 3])
    end
  end

  describe "#format_table_row" do
    it "formats row with proper padding" do
      row = ["Alice", "30"]
      widths = [10, 5]

      result = cli.send(:format_table_row, row, widths)
      expect(result).to eq("Alice       30   ")
    end
  end

  describe "#separator_line" do
    it "generates separator line with correct lengths" do
      widths = [5, 3, 10]
      result = cli.send(:separator_line, widths)
      expect(result).to eq("-----  ---  ----------")
    end
  end

  describe "COLORS" do
    it "defines expected color codes" do
      expect(described_class::COLORS).to include(
        red: 31,
        green: 32,
        yellow: 33,
        blue: 34,
        magenta: 35,
        cyan: 36
      )
    end

    it "is frozen" do
      expect(described_class::COLORS).to be_frozen
    end
  end
end
