# frozen_string_literal: true

module GuidedSetup::Validations
  extend ActiveSupport::Concern

  included do
    validates :account_id, uniqueness: true
    validate :scheduling_preferences_shape
  end

  private

  def scheduling_preferences_shape
    return if scheduling_preferences.blank?
    return errors.add(:scheduling_preferences, "must be a hash") unless scheduling_preferences.is_a?(Hash)

    validate_scheduling_timezone
    validate_scheduling_days
    validate_scheduling_time_blocks
  end

  def validate_scheduling_timezone
    tz = scheduling_preferences[SchedulingPreferences::TIMEZONE_KEY]
    return if tz.blank?

    errors.add(:scheduling_preferences, "has unknown timezone") unless ActiveSupport::TimeZone[tz]
  end

  def validate_scheduling_days
    days = Array(scheduling_preferences[SchedulingPreferences::DAYS_KEY])
    return if (days - SchedulingPreferences::DAYS_OF_WEEK).empty?

    errors.add(:scheduling_preferences, "has unknown day-of-week values")
  end

  def validate_scheduling_time_blocks
    blocks = Array(scheduling_preferences[SchedulingPreferences::TIME_BLOCKS_KEY])
    return if (blocks - SchedulingPreferences::TIME_BLOCKS).empty?

    errors.add(:scheduling_preferences, "has unknown time-block values")
  end
end
