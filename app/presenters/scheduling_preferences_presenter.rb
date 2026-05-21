# frozen_string_literal: true

# Wraps a GuidedSetup#scheduling_preferences hash for view rendering: the
# offer/booking form (re-render after error or repeat visit) and the
# kickoff-booked confirmation page. Keeps the views free of "either the
# draft or the stored prefs, then pull these keys, then coerce arrays"
# arithmetic.
class SchedulingPreferencesPresenter
  def self.from(prefs)
    new(prefs.presence || {})
  end

  def initialize(prefs)
    @prefs = prefs
  end

  def timezone
    prefs[SchedulingPreferences::TIMEZONE_KEY].to_s
  end

  def days
    Array(prefs[SchedulingPreferences::DAYS_KEY])
  end

  def time_blocks
    Array(prefs[SchedulingPreferences::TIME_BLOCKS_KEY])
  end

  def day_selected?(day)
    days.include?(day)
  end

  def time_block_selected?(block)
    time_blocks.include?(block)
  end

  def any_days?
    days.any?
  end

  def any_time_blocks?
    time_blocks.any?
  end

  def day_labels
    days.map { |d| SchedulingPreferences::DAY_LABELS.fetch(d, d.to_s.capitalize) }.join(", ")
  end

  def time_block_labels
    time_blocks.map { |b| SchedulingPreferences::TIME_BLOCK_LABELS.fetch(b, b.to_s.capitalize) }.join(", ")
  end

  private

  attr_reader :prefs
end
