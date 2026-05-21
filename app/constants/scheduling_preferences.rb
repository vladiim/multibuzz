# frozen_string_literal: true

# Shape of GuidedSetup#scheduling_preferences (jsonb). Captured on the
# confirmation step after Guided Setup purchase so the specialist knows
# when to reach out for the kickoff call.
module SchedulingPreferences
  TIMEZONE_KEY = "timezone"
  DAYS_KEY = "days"
  TIME_BLOCKS_KEY = "time_blocks"

  DAYS_OF_WEEK = %w[mon tue wed thu fri sat sun].freeze

  TIME_BLOCKS = %w[morning midday afternoon evening].freeze

  DAY_LABELS = {
    "mon" => "Mon",
    "tue" => "Tue",
    "wed" => "Wed",
    "thu" => "Thu",
    "fri" => "Fri",
    "sat" => "Sat",
    "sun" => "Sun"
  }.freeze

  TIME_BLOCK_LABELS = {
    "morning"   => "Morning",
    "midday"    => "Midday",
    "afternoon" => "Afternoon",
    "evening"   => "Evening"
  }.freeze

  TIME_BLOCK_HOURS = {
    "morning"   => "6am-12pm",
    "midday"    => "12pm-3pm",
    "afternoon" => "3pm-6pm",
    "evening"   => "6pm-9pm"
  }.freeze
end
