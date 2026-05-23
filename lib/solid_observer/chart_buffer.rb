# frozen_string_literal: true

module SolidObserver
  class ChartBuffer
    INSTANCE_MUTEX = Mutex.new

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

    def initialize
      @mutex = Mutex.new
      @samples = []
      @cap = nil
    end

    def append(value, at: Time.now)
      sample = {t: at.to_i, v: value.to_i}

      @mutex.synchronize { store_sample(sample) }

      sample
    end

    def recent(window_seconds)
      cutoff = Time.now.to_i - window_seconds.to_i

      @mutex.synchronize do
        @samples.select { |sample| sample[:t] >= cutoff }.map(&:dup)
      end
    end

    def clear
      @mutex.synchronize do
        @samples.clear
        @cap = nil
      end
    end

    private

    def store_sample(sample)
      @cap ||= compute_cap
      replace_or_append(sample)
      trim_to_cap
    end

    def replace_or_append(sample)
      latest_sample = @samples.last

      if latest_sample && latest_sample[:t] == sample[:t]
        @samples[-1] = sample
      else
        @samples << sample
      end
    end

    def trim_to_cap
      overflow = @samples.length - @cap
      @samples.shift(overflow) if overflow.positive?
    end

    def compute_cap
      (3600 / 5).to_i # 720 samples — 1h at the 5s cadence
    end
  end
end
