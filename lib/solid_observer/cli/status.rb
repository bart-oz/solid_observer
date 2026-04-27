# frozen_string_literal: true

module SolidObserver
  module CLI
    class Status < Base
      BANNER_ICON_TOP = "         ┌─   ─┐"
      BANNER_ICON_MID_LEFT = "            ◉"
      BANNER_ICON_BOT = "         └─   ─┘"
      BANNER_NAME = "solid_observer"
      BANNER_NAME_GAP = "     "

      def call
        print_banner
        print_header
        print_queue_stats
      end

      private

      def print_banner
        output(BANNER_ICON_TOP, color: :red)
        output(banner_middle_line)
        output(BANNER_ICON_BOT, color: :red)
      end

      def banner_middle_line
        icon = color_enabled? ? colorize(BANNER_ICON_MID_LEFT, :red) : BANNER_ICON_MID_LEFT
        "#{icon}#{BANNER_NAME_GAP}#{BANNER_NAME}"
      end

      def print_header
        output("\n📊 SolidObserver Status", color: :red)
        output("=" * 50, color: :red)
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
