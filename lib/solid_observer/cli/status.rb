# frozen_string_literal: true

module SolidObserver
  module CLI
    class Status < Base
      def call
        print_header
        print_queue_stats
      end

      private

      def print_header
        output("\n📊 SolidObserver Status", color: :cyan)
        output("=" * 50, color: :cyan)
        output("")
      end

      def print_queue_stats
        stats = SolidObserver::QueueStats.snapshot

        if stats[:available]
          print_queue_table(stats)
          print_queue_depths(stats[:queues]) if stats[:queues].any?
        else
          warning("⚠️  SolidQueue not available: #{stats[:error]}")
        end
      end

      def print_queue_table(stats)
        output("🚀 Solid Queue", color: :green)
        output("")

        table(
          headers: ["Metric", "Value"],
          rows: [
            ["Ready", stats[:ready]],
            ["Scheduled", stats[:scheduled]],
            ["Claimed", stats[:claimed]],
            ["Failed", stats[:failed]],
            ["Workers", stats[:workers]]
          ]
        )
        output("")
      end

      def print_queue_depths(queues)
        output("📋 Queue Depths", color: :green)
        output("")

        table(
          headers: ["Queue", "Jobs"],
          rows: queues.sort_by { |name, _count| name }.map { |name, count| [name, count] }
        )
        output("")
      end
    end
  end
end
