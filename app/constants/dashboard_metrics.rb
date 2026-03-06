# frozen_string_literal: true

module DashboardMetrics
  CONVERSIONS = "conversions"
  REVENUE = "revenue"
  AOV = "aov"
  AVG_DAYS = "avg_days"
  AVG_CHANNELS = "avg_channels"
  AVG_VISITS = "avg_visits"
  CREDITS = "credits"

  ALL = [
    CONVERSIONS,
    REVENUE,
    AOV,
    AVG_DAYS,
    AVG_CHANNELS,
    AVG_VISITS
  ].freeze

  DEFAULT = CONVERSIONS

  # Maps selected metric → chart controller key
  # "conversions" uses "credits" internally in the chart controller
  CHART_KEY = {
    CONVERSIONS => CREDITS,
    REVENUE => REVENUE,
    AOV => AOV,
    AVG_CHANNELS => AVG_CHANNELS,
    AVG_VISITS => AVG_VISITS,
    AVG_DAYS => AVG_DAYS
  }.freeze

  CHART_TITLES = {
    CONVERSIONS => "Conversions",
    REVENUE => "Revenue",
    AOV => "Avg Order Value",
    AVG_CHANNELS => "Avg Channels",
    AVG_VISITS => "Avg Visits",
    AVG_DAYS => "Avg Days"
  }.freeze

  def self.chart_key_for(metric)
    CHART_KEY.fetch(metric, CREDITS)
  end

  def self.chart_title_for(metric)
    CHART_TITLES.fetch(metric, "Conversions")
  end
end
