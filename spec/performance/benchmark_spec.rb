# frozen_string_literal: true

require "spec_helper"
require "benchmark"

RSpec.describe "Performance Benchmarks", type: :performance do
  before(:all) do
    queue_connection = SolidObserver::QueueEvent.connection

    if queue_connection.table_exists?(:solid_observer_queue_events)
      queue_connection.drop_table(:solid_observer_queue_events)
    end

    queue_connection.create_table :solid_observer_queue_events do |t|
      t.string :event_type, null: false, limit: 50
      t.string :job_class, limit: 100
      t.string :queue_name, limit: 50
      t.string :correlation_id, limit: 64
      t.text :metadata
      t.float :duration
      t.datetime :recorded_at, null: false

      t.index :recorded_at
      t.index :correlation_id, where: "correlation_id IS NOT NULL"
      t.index :event_type
      t.index :job_class
      t.index :queue_name
    end

    @original_buffer_size = SolidObserver.config.buffer_size
    @original_max_buffer_size = SolidObserver.config.max_buffer_size
    SolidObserver.config.max_buffer_size = 100_000
    SolidObserver.config.buffer_size = 100_000
  end

  after(:all) do
    SolidObserver.config.buffer_size = @original_buffer_size if @original_buffer_size
    SolidObserver.config.max_buffer_size = @original_max_buffer_size if @original_max_buffer_size
  end

  let(:buffer) { SolidObserver::QueueEventBuffer.instance }

  before do
    SolidObserver::QueueEvent.delete_all
    buffer.clear
  end

  describe "event insertion performance" do
    it "inserts individual events under 5ms average" do
      times = 100.times.map do
        event_data = {
          event_type: "job_completed",
          job_class: "TestJob",
          queue_name: "default",
          correlation_id: SecureRandom.uuid,
          recorded_at: Time.current,
          duration: rand(0.1..5.0).round(3),
          metadata: {job_id: SecureRandom.uuid, attempts: 1}.to_json
        }

        Benchmark.realtime do
          SolidObserver::QueueEvent.insert_all!([event_data])
        end * 1000
      end

      avg_time = times.sum / times.size
      max_time = times.max
      min_time = times.min

      puts "\n  Event insertion stats:"
      puts "    Average: #{avg_time.round(2)}ms"
      puts "    Min: #{min_time.round(2)}ms"
      puts "    Max: #{max_time.round(2)}ms"

      expect(avg_time).to be < 5, "Average insertion time #{avg_time.round(2)}ms exceeds 5ms threshold" if ENV["PERF_STRICT"]
    end
  end

  describe "buffer performance" do
    it "pushes 10,000 events to buffer and flushes under 5 seconds" do
      events_count = 10_000

      total_time = Benchmark.realtime do
        events_count.times do |i|
          buffer.push(
            event_type: "job_completed",
            job_class: "BenchmarkJob",
            queue_name: "default",
            correlation_id: "bench-#{i}",
            recorded_at: Time.current,
            duration: rand(0.1..2.0).round(3),
            metadata: {index: i}.to_json
          )
        end

        buffer.flush!
      end

      stored_count = SolidObserver::QueueEvent.count

      puts "\n  Buffer flush stats (#{events_count} events):"
      puts "    Total time: #{total_time.round(2)}s"
      puts "    Events/second: #{(events_count / total_time).round(0)}"
      puts "    Stored events: #{stored_count}"

      expect(total_time).to be < 5, "Buffer flush time #{total_time.round(2)}s exceeds 5s threshold" if ENV["PERF_STRICT"]
      expect(stored_count).to eq(events_count)
    end

    it "handles concurrent buffer pushes safely" do
      events_per_thread = 500
      thread_count = 4
      total_events = events_per_thread * thread_count
      total_time = Benchmark.realtime do
        threads = thread_count.times.map do |thread_id|
          Thread.new do
            events_per_thread.times do |i|
              buffer.push(
                event_type: "job_completed",
                job_class: "ConcurrentJob",
                queue_name: "concurrent",
                correlation_id: "thread-#{thread_id}-#{i}",
                recorded_at: Time.current,
                duration: nil,
                metadata: {thread: thread_id, index: i}.to_json
              )
            end
          end
        end

        threads.each(&:join)
      end

      buffered_count = buffer.size

      puts "\n  Concurrent buffer push stats (#{thread_count} threads, #{events_per_thread} events each):"
      puts "    Total time: #{total_time.round(2)}s"
      puts "    Events/second: #{(total_events / total_time).round(0)}"
      puts "    Buffered events: #{buffered_count}"

      expect(buffered_count).to eq(total_events)

      flush_time = Benchmark.realtime { buffer.flush! }
      stored_count = SolidObserver::QueueEvent.count

      puts "    Flush time: #{flush_time.round(2)}s"
      puts "    Stored events: #{stored_count}"

      expect(stored_count).to eq(total_events)
    end
  end

  describe "query performance" do
    before do
      events = 1000.times.map do |i|
        {
          event_type: %w[job_enqueued job_completed job_failed].sample,
          job_class: ["FastJob", "SlowJob", "CriticalJob"].sample,
          queue_name: %w[default priority background].sample,
          correlation_id: "query-bench-#{i}",
          recorded_at: Time.current - rand(0..3600),
          duration: rand(0.1..10.0).round(3),
          metadata: {batch: i / 100}.to_json
        }
      end

      SolidObserver::QueueEvent.insert_all!(events)
    end

    it "queries events by event_type under 50ms" do
      time = Benchmark.realtime do
        SolidObserver::QueueEvent.where(event_type: "job_completed").count
      end * 1000

      puts "\n  Query by event_type: #{time.round(2)}ms"
      expect(time).to be < 50 if ENV["PERF_STRICT"]
    end

    it "queries events by job_class under 50ms" do
      time = Benchmark.realtime do
        SolidObserver::QueueEvent.where(job_class: "FastJob").count
      end * 1000

      puts "\n  Query by job_class: #{time.round(2)}ms"
      expect(time).to be < 50 if ENV["PERF_STRICT"]
    end

    it "queries events by correlation_id under 50ms" do
      time = Benchmark.realtime do
        SolidObserver::QueueEvent.find_by(correlation_id: "query-bench-500")
      end * 1000

      puts "\n  Query by correlation_id: #{time.round(2)}ms"
      expect(time).to be < 50 if ENV["PERF_STRICT"]
    end

    it "queries events with date range under 50ms" do
      time = Benchmark.realtime do
        SolidObserver::QueueEvent.where(
          recorded_at: 1.hour.ago..Time.current
        ).count
      end * 1000

      puts "\n  Query by date range: #{time.round(2)}ms"
      expect(time).to be < 50 if ENV["PERF_STRICT"]
    end
  end

  describe "QueueStats performance" do
    it "returns snapshot quickly when SolidQueue unavailable" do
      time = Benchmark.realtime do
        SolidObserver::QueueStats.snapshot
      end * 1000

      puts "\n  QueueStats.snapshot (no SolidQueue): #{time.round(2)}ms"
      expect(time).to be < 10 if ENV["PERF_STRICT"]
    end
  end

  describe "bulk operations" do
    it "inserts 1000 events via insert_all! under 500ms" do
      events = 1000.times.map do |i|
        {
          event_type: "job_completed",
          job_class: "BulkJob",
          queue_name: "bulk",
          correlation_id: "bulk-#{i}",
          recorded_at: Time.current,
          duration: rand(0.1..1.0).round(3),
          metadata: {}.to_json
        }
      end

      time = Benchmark.realtime do
        SolidObserver::QueueEvent.insert_all!(events)
      end * 1000

      puts "\n  Bulk insert (1000 events): #{time.round(2)}ms"
      puts "    Events/second: #{(1000 / (time / 1000)).round(0)}"

      expect(time).to be < 500 if ENV["PERF_STRICT"]
    end

    it "deletes old events efficiently" do
      old_events = 500.times.map do |i|
        {
          event_type: "job_completed",
          job_class: "OldJob",
          queue_name: "default",
          correlation_id: "old-#{i}",
          recorded_at: 8.days.ago,
          duration: nil,
          metadata: {}.to_json
        }
      end
      SolidObserver::QueueEvent.insert_all!(old_events)

      initial_count = SolidObserver::QueueEvent.count

      time = Benchmark.realtime do
        SolidObserver::QueueEvent.where("recorded_at < ?", 7.days.ago).delete_all
      end * 1000

      final_count = SolidObserver::QueueEvent.count
      deleted = initial_count - final_count

      puts "\n  Delete old events (#{deleted} deleted): #{time.round(2)}ms"

      expect(time).to be < 100 if ENV["PERF_STRICT"]
      expect(deleted).to eq(500)
    end
  end
end
