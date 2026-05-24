# frozen_string_literal: true

# Mirrors live_poll.js Sparkline.render — keep in sync.
module SolidObserver
  module DashboardHelper
    SVG_W = 120
    SVG_H = 32

    def spark_points(series, width: SVG_W, height: SVG_H)
      return "" if series.blank?

      t_min = series.first[:t]
      t_max = series.last[:t]
      v_max = [series.max_by { |point| point[:v] }[:v], 1].max
      time_span = t_max - t_min

      series.map { |point|
        val = point[:v]
        point_x = time_span.zero? ? width / 2.0 : ((point[:t] - t_min).to_f / time_span) * (width - 2) + 1
        point_y = height - 1 - (val.to_f / v_max) * (height - 2)
        format("%.1f,%.1f", point_x, point_y)
      }.join(" ")
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
