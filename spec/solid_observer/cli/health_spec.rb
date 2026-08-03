# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::CLI::Health do
  let(:health) { described_class.new }

  def stub_health(overall:, components:)
    allow(SolidObserver::Services::HealthScore).to receive(:call)
      .and_return({overall: overall, components: components})
  end

  describe "#call" do
    context "when every component is stable" do
      before do
        stub_health(
          overall: :stable,
          components: {
            queue: {status: :stable, available: true},
            cache: {status: :stable, available: true}
          }
        )
      end

      it "displays the header" do
        expect { health.call }.to output(/🩺 SolidObserver Health/).to_stdout
      end

      it "displays the aggregate status" do
        expect { health.call }.to output(/Overall: stable/).to_stdout
      end

      it "displays one row per component" do
        output = capture_stdout { health.call }

        expect(output).to match(/queue\s+stable/)
        expect(output).to match(/cache\s+stable/)
      end

      it "does not mark available components as unavailable" do
        expect(capture_stdout { health.call }).not_to include("(unavailable)")
      end
    end

    context "when a component is degraded" do
      before do
        stub_health(
          overall: :degraded,
          components: {queue: {status: :degraded, available: true}}
        )
      end

      it "reports the degraded aggregate verbatim" do
        expect { health.call }.to output(/Overall: degraded/).to_stdout
      end

      it "reports the degraded component" do
        expect(capture_stdout { health.call }).to match(/queue\s+degraded/)
      end
    end

    context "when a component is critical" do
      before do
        stub_health(
          overall: :critical,
          components: {queue: {status: :critical, available: true}}
        )
      end

      it "reports the critical aggregate" do
        expect { health.call }.to output(/Overall: critical/).to_stdout
      end

      it "completes without raising and without altering exit status" do
        expect { capture_stdout { health.call } }.not_to raise_error
      end
    end

    context "when a component is unavailable" do
      before do
        stub_health(
          overall: :degraded,
          components: {
            cable: {status: :degraded, available: false},
            queue: {status: :stable, available: true}
          }
        )
      end

      it "marks the unavailable component instead of omitting it" do
        expect(capture_stdout { health.call }).to match(/cable\s+degraded\s+\(unavailable\)/)
      end

      it "still reports sibling components" do
        expect(capture_stdout { health.call }).to match(/queue\s+stable/)
      end
    end

    context "when no components are enabled" do
      before { stub_health(overall: :stable, components: {}) }

      it "prints an explicit no-components note" do
        expect(capture_stdout { health.call }).to include("No components enabled")
      end

      it "still prints the aggregate" do
        expect(capture_stdout { health.call }).to match(/Overall: stable/)
      end

      it "does not raise" do
        expect { capture_stdout { health.call } }.not_to raise_error
      end
    end

    context "when an unrecognised status is returned" do
      before do
        stub_health(
          overall: :unknown,
          components: {queue: {status: :unknown, available: true}}
        )
      end

      it "renders the status verbatim without coercing it to stable" do
        output = capture_stdout { health.call }

        expect(output).to match(/Overall: unknown/)
        expect(output).not_to match(/stable/)
      end
    end

    context "with a non-TTY stdout" do
      before do
        stub_health(
          overall: :critical,
          components: {queue: {status: :critical, available: true}}
        )
      end

      it "emits no ANSI escape sequences" do
        expect(capture_stdout { health.call }).not_to include("\e[")
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
