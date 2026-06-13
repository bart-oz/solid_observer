# frozen_string_literal: true

require "spec_helper"

RSpec.describe SolidObserver::ChartBuffer do
  let(:cache_store) { ActiveSupport::Cache::MemoryStore.new }

  before do
    allow(Rails).to receive(:cache).and_return(cache_store)
    described_class.clear
  end

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

    it "shares samples across distinct instances via shared cache storage" do
      first_instance = described_class.new
      second_instance = described_class.new
      sample_time = Time.utc(2026, 5, 10, 12, 0, 0)

      travel_to(sample_time) do
        first_instance.append(11, at: sample_time)

        expect(second_instance.recent(60)).to eq(
          [{t: sample_time.to_i, v: 11}]
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

    it "falls back to shared process-local storage when cache access fails" do
      broken_cache_store = instance_double(ActiveSupport::Cache::Store)
      first_instance = described_class.new
      second_instance = described_class.new
      sample_time = Time.utc(2026, 5, 10, 12, 0, 0)

      allow(Rails).to receive(:cache).and_return(broken_cache_store)
      allow(broken_cache_store).to receive(:read).and_raise(StandardError, "cache unavailable")
      allow(broken_cache_store).to receive(:write).and_raise(StandardError, "cache unavailable")
      allow(broken_cache_store).to receive(:delete).and_raise(StandardError, "cache unavailable")

      travel_to(sample_time) do
        first_instance.append(12, at: sample_time)

        expect(second_instance.recent(60)).to eq(
          [{t: sample_time.to_i, v: 12}]
        )

        second_instance.clear

        expect(first_instance.recent(60)).to eq([])
      end
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
