# frozen_string_literal: true

# Mirrors live_poll.js Sparkline.render — keep in sync.
module SolidObserver
  module DashboardHelper
    SVG_W = 120
    SVG_H = 32

    def spark_points(series, width: SVG_W, height: SVG_H)
      return "" if series.blank?

      context = build_spark_context(series, width, height)
      series.map { |point| format_spark_point(point: point, context: context) }.join(" ")
    end

    def build_spark_context(series, width, height)
      first_point = series.first
      last_point = series.last
      min_time = first_point[:t]

      {
        min_time: min_time,
        time_span: last_point[:t] - min_time,
        max_value: [series.max_by { |point| point[:v] }[:v], 1].max,
        width: width,
        height: height,
        inner_width: width - 2,
        inner_height: height - 2
      }
    end

    def format_spark_point(point:, context:)
      time_span = context[:time_span]
      coordinate_x = if time_span.zero?
        context[:width] / 2.0
      else
        ((point[:t] - context[:min_time]).to_f / time_span) * context[:inner_width] + 1
      end

      coordinate_y = context[:height] - 1 - (point[:v].to_f / context[:max_value]) * context[:inner_height]
      format("%.1f,%.1f", coordinate_x, coordinate_y)
    end

    RANGE_LABELS = {
      "15m" => "in last 15m",
      "30m" => "in last 30m",
      "1h" => "in last hour",
      "7h" => "in last 7h",
      "1d" => "in last day",
      "7d" => "in last 7d",
      "14d" => "in last 14d"
    }.freeze

    def range_label(range_key)
      RANGE_LABELS.fetch(range_key, "in selected range")
    end
  end
end
