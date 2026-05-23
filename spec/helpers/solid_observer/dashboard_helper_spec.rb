# frozen_string_literal: true

require "spec_helper"
require_relative "../../../app/helpers/solid_observer/dashboard_helper"

RSpec.describe SolidObserver::DashboardHelper do
  include described_class

  describe "#spark_points" do
    it "returns empty string for empty series" do
      expect(spark_points([])).to eq("")
    end

    it "returns midpoint x and height-mapped y for a single sample" do
      result = spark_points([{t: 100, v: 5}])
      # t_min == t_max → x = width/2 = 60.0
      # v_max = max(5, 1) = 5
      # y = 32 - 1 - (5/5)*(32-2) = 31 - 30 = 1.0
      expect(result).to eq("60.0,1.0")
    end

    it "projects multi-sample monotonic series matching the JS Sparkline.render formula" do
      series = [
        {t: 0, v: 0},
        {t: 10, v: 5},
        {t: 20, v: 10},
        {t: 30, v: 15},
        {t: 40, v: 20}
      ]
      result = spark_points(series)
      points = result.split(" ")

      # t_min=0, t_max=40, v_max=max(0,5,10,15,20)=20 → v_max=max(20,1)=20
      # x = ((t - 0) / (40 - 0)) * (120 - 2) + 1 = (t/40)*118 + 1
      # y = 32 - 1 - (v/20)*(32-2) = 31 - v*1.5

      # Point 0: t=0, v=0 → x=1.0, y=31.0
      expect(points[0]).to eq("1.0,31.0")
      # Point 1: t=10, v=5 → x=(10/40)*118+1=30.5, y=31-7.5=23.5
      expect(points[1]).to eq("30.5,23.5")
      # Point 2: t=20, v=10 → x=(20/40)*118+1=60.0, y=31-15=16.0
      expect(points[2]).to eq("60.0,16.0")
      # Point 3: t=30, v=15 → x=(30/40)*118+1=89.5, y=31-22.5=8.5
      expect(points[3]).to eq("89.5,8.5")
      # Point 4: t=40, v=20 → x=(40/40)*118+1=119.0, y=31-30=1.0
      expect(points[4]).to eq("119.0,1.0")
    end

    it "floors v_max at 1 to prevent division by zero on all-zero series" do
      series = [
        {t: 0, v: 0},
        {t: 10, v: 0},
        {t: 20, v: 0}
      ]
      result = spark_points(series)
      points = result.split(" ")

      # v_max = max(0, 1) = 1
      # y = 32 - 1 - (0/1)*(32-2) = 31.0 for all points
      expect(points[0]).to end_with(",31.0")
      expect(points[1]).to end_with(",31.0")
      expect(points[2]).to end_with(",31.0")
    end

    it "falls back to midpoint x when t_min equals t_max" do
      series = [
        {t: 50, v: 3},
        {t: 50, v: 7}
      ]
      result = spark_points(series)
      points = result.split(" ")

      # t_min == t_max → x = 120/2.0 = 60.0 for all points
      # v_max = max(3, 7) = 7
      # Point 0: v=3 → y = 32-1-(3/7)*30 = 31-12.857... ≈ 18.1
      # Point 1: v=7 → y = 32-1-(7/7)*30 = 31-30 = 1.0
      expect(points[0]).to start_with("60.0,")
      expect(points[1]).to eq("60.0,1.0")
    end

    it "accepts custom width and height parameters" do
      series = [{t: 0, v: 5}, {t: 10, v: 10}]
      result = spark_points(series, width: 200, height: 50)
      points = result.split(" ")

      # t_min=0, t_max=10, v_max=10
      # x = ((t-0)/(10-0))*(200-2)+1 = (t/10)*198+1
      # y = 50-1-(v/10)*(50-2) = 49-v*4.8

      # Point 0: t=0, v=5 → x=1.0, y=49-24.0=25.0
      expect(points[0]).to eq("1.0,25.0")
      # Point 1: t=10, v=10 → x=199.0, y=49-48.0=1.0
      expect(points[1]).to eq("199.0,1.0")
    end
  end
end
