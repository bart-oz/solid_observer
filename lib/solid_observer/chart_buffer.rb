# frozen_string_literal: true

module SolidObserver
  class ChartBuffer
    CACHE_KEY = "solid_observer/chart_buffer/ready_samples"
    INSTANCE_MUTEX = Mutex.new
    SAMPLE_CAP = 720
    STORAGE_MUTEX = Mutex.new

    class SampleWindow
      def initialize(samples)
        @samples = samples
      end

      def upsert(sample, cap:)
        return replace_latest_sample(sample) if latest_sample_timestamp == sample[:t]

        append_new_sample(sample, cap: cap)
      end

      private

      def latest_sample_timestamp
        @samples.last&.[](:t)
      end

      def replace_latest_sample(sample)
        @samples[-1] = sample
        @samples
      end

      def append_new_sample(sample, cap:)
        @samples << sample
        overflow = @samples.length - cap
        @samples.shift(overflow) if overflow.positive?
        @samples
      end
    end

    class << self
      def append(value, at: Time.now)
        instance.append(value, at: at)
      end

      def recent(window_seconds)
        instance.recent(window_seconds)
      end

      def clear
        instance.clear
      end

      private

      def instance
        INSTANCE_MUTEX.synchronize { @instance ||= new }
      end
    end

    @fallback_samples = []

    def append(value, at: Time.now)
      sample = {t: at.to_i, v: value.to_i}

      STORAGE_MUTEX.synchronize { persist_sample(sample) }

      sample
    end

    def recent(window_seconds)
      cutoff = Time.now.to_i - window_seconds.to_i

      STORAGE_MUTEX.synchronize do
        load_samples.select { |sample| sample[:t] >= cutoff }.map(&:dup)
      end
    end

    def clear
      STORAGE_MUTEX.synchronize do
        empty_samples = []
        replace_fallback_samples(empty_samples)
        cache_store&.delete(CACHE_KEY)
      rescue
        nil
      end
    end

    private

    def persist_sample(sample)
      samples = SampleWindow.new(load_samples).upsert(sample, cap: SAMPLE_CAP)
      write_samples(samples)
    end

    def load_samples
      normalize_samples(cache_store&.read(CACHE_KEY) || stored_fallback_samples)
    rescue
      stored_fallback_samples
    end

    def write_samples(samples)
      normalized = normalize_samples(samples)

      replace_fallback_samples(normalized.map(&:dup))
      cache_store&.write(CACHE_KEY, normalized)
    rescue
      replace_fallback_samples(normalized)
    end

    def cache_store
      return unless defined?(Rails)

      Rails.cache
    end

    def stored_fallback_samples
      normalize_samples(self.class.instance_variable_get(:@fallback_samples))
    end

    def replace_fallback_samples(samples)
      self.class.instance_variable_set(:@fallback_samples, samples)
    end

    def normalize_samples(samples)
      Array(samples).filter_map do |sample|
        normalize_sample(sample)
      end.last(SAMPLE_CAP)
    end

    def normalize_sample(sample)
      return unless sample.is_a?(Hash)

      timestamp = sample[:t] || sample["t"]
      value = sample[:v] || sample["v"]
      return unless timestamp && value

      {t: timestamp.to_i, v: value.to_i}
    end
  end
end
