# frozen_string_literal: true

module DashboardTabs
  CONVERSIONS = "conversions"
  FUNNEL = "funnel"
  SPEND = "spend"
  EVENTS = "events"

  ALL = [
    CONVERSIONS,
    FUNNEL,
    SPEND,
    EVENTS
  ].freeze

  EXPORTABLE = [
    CONVERSIONS,
    FUNNEL,
    SPEND
  ].freeze
end
