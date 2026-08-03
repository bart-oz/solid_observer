# frozen_string_literal: true

module SolidObserver
  module CLI
    class Health < Base
      STATUS_COLORS = {stable: :green, degraded: :yellow, critical: :red}.freeze
      NAME_WIDTH = 8
      UNAVAILABLE_SUFFIX = "  (unavailable)"

      def call
        health = SolidObserver::Services::HealthScore.call

        print_header
        print_overall(health[:overall])
        print_components(health[:components])
        output("")
      end

      private

      def print_header
        output("\n🩺 SolidObserver Health", color: :red)
        output("=" * 50, color: :red)
        output("")
      end

      def print_overall(overall)
        output("Overall: #{overall}", color: STATUS_COLORS[overall])
        output("")
      end

      def print_components(components)
        return warning("⚠️  No components enabled") if components.empty?

        output("Components", color: :green)
        output("")
        components.each { |name, entry| print_component(name, entry[:status], entry[:available]) }
      end

      # Renders the status verbatim: HealthScore owns the worst-of ladder, so an
      # unrecognised status stays uncoloured rather than being coerced to stable.
      # :reek:ControlParameter
      def print_component(name, status, available)
        suffix = available ? "" : UNAVAILABLE_SUFFIX
        output("  #{name.to_s.ljust(NAME_WIDTH)}#{status}#{suffix}", color: STATUS_COLORS[status])
      end
    end
  end
end
