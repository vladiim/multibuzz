# frozen_string_literal: true

module SpendIntelligence
  class LinearRegression
    MIN_POINTS = 2

    def initialize(points)
      @points = points
    end

    def slope = @slope ||= sufficient? ? raw_slope : 0
    def intercept = @intercept ||= sufficient? ? raw_intercept : 0

    private

    attr_reader :points

    def sufficient? = points.size >= MIN_POINTS
    def n = points.size
    def sum_x = @sum_x ||= points.sum(&:first)
    def sum_y = @sum_y ||= points.sum(&:last)
    def sum_xy = @sum_xy ||= points.sum { |x, y| x * y }
    def sum_x2 = @sum_x2 ||= points.sum { |x, _| x**2 }
    def denominator = @denominator ||= n * sum_x2 - sum_x**2
    def raw_slope = denominator.zero? ? 0 : (n * sum_xy - sum_x * sum_y) / denominator
    def raw_intercept = (sum_y - slope * sum_x) / n
  end
end
