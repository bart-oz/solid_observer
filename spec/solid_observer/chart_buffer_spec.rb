# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::ChartBuffer do
  after do
    described_class.clear
    SolidObserver.reset_configuration!
  end

  describe ".append and .recent" do
    it "stores samples and returns them from recent windows" do
      travel_to(Time.utc(2026, 5, 10, 12, 0, 0)) do
        described_class.append(4, at: Time.current)
        described_class.append(7, at: 20.seconds.from_now)

        expect(described_class.recent(30)).to eq(
          [
            {t: Time.utc(2026, 5, 10, 12, 0, 0).to_i, v: 4},
            {t: Time.utc(2026, 5, 10, 12, 0, 20).to_i, v: 7}
          ]
        )
      end
    end
  end

  describe ".append" do
    it "enforces cap of 720 samples (1h at 5s cadence)" do
      start_time = Time.utc(2026, 5, 10, 12, 0, 0)

      725.times do |index|
        described_class.append(index, at: start_time + index.seconds)
      end

      samples = described_class.recent(10.years.to_i)
      expect(samples.size).to eq(720)
      expect(samples.first).to eq({t: (start_time + 5.seconds).to_i, v: 5})
      expect(samples.last).to eq({t: (start_time + 724.seconds).to_i, v: 724})
    end

    it "deduplicates same-second samples by replacing the latest value" do
      at_time = Time.utc(2026, 5, 10, 12, 0, 0)

      travel_to(at_time) do
        described_class.append(2, at: at_time)
        described_class.append(9, at: at_time + 0.5)

        expect(described_class.recent(60)).to eq(
          [{t: at_time.to_i, v: 9}]
        )
      end
    end

    it "is safe under concurrent appends" do
      start_time = Time.utc(2026, 5, 10, 12, 0, 0)

      threads = 4.times.map do |thread_index|
        Thread.new do
          100.times do |sample_index|
            timestamp = start_time + (thread_index * 100 + sample_index).seconds
            described_class.append(sample_index, at: timestamp)
          end
        end
      end
      threads.each(&:value)

      samples = described_class.recent(10.years.to_i)
      expect(samples.size).to eq(400)
      expect(samples).to all(include(:t, :v))
    end
  end

  describe ".clear" do
    it "resets buffer state" do
      described_class.append(3, at: Time.utc(2026, 5, 10, 12, 0, 0))

      described_class.clear

      expect(described_class.recent(60)).to eq([])
    end
  end
end
