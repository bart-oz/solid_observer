# frozen_string_literal: true

module SolidObserver
  module CLI
    class Base
      class << self
        def call(*args, **kwargs)
          new.call(*args, **kwargs)
        end
      end

      def call
        raise NotImplementedError, "#{self.class} must implement #call"
      end

      private

      def output(text, color: nil)
        text = colorize(text, color) if color && color_enabled?
        puts text
      end

      def error(text)
        output(text, color: :red)
      end

      def success(text)
        output(text, color: :green)
      end

      def warning(text)
        output(text, color: :yellow)
      end

      def info(text)
        output(text, color: :blue)
      end

      def table(headers:, rows:)
        return if rows.empty?

        widths = calculate_column_widths(headers, rows)

        output(format_table_row(headers, widths), color: :cyan)
        output(separator_line(widths), color: :cyan)

        rows.each do |row|
          output(format_table_row(row, widths))
        end
      end

      def confirm(question, default: true)
        prompt = default ? "(Y/n)" : "(y/N)"
        output("#{question} #{prompt} ", color: :yellow)
        print "> "

        response = $stdin.gets&.strip&.downcase

        return default if response.nil? || response.empty?

        response.start_with?("y")
      end

      def color_enabled?
        $stdout.tty?
      end

      def colorize(text, color)
        return text unless color

        color_code = COLORS[color]
        return text unless color_code

        "\e[#{color_code}m#{text}\e[0m"
      end

      def calculate_column_widths(headers, rows)
        all_rows = [headers] + rows
        all_rows.transpose.map { |column| column.map(&:to_s).map(&:length).max }
      end

      def format_table_row(row, widths)
        row.map.with_index { |cell, i| cell.to_s.ljust(widths[i]) }.join("  ")
      end

      def separator_line(widths)
        widths.map { |width| "-" * width }.join("  ")
      end

      COLORS = {
        red: 31,
        green: 32,
        yellow: 33,
        blue: 34,
        magenta: 35,
        cyan: 36
      }.freeze
    end
  end
end
