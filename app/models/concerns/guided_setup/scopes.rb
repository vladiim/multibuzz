# frozen_string_literal: true

module GuidedSetup::Scopes
  extend ActiveSupport::Concern

  # An in-progress engagement with no milestone stamped in this long is
  # surfaced to the team as stalled, for proactive outreach.
  STALLED_AFTER = 14.days

  included do
    scope :stalled, -> { in_progress.where(updated_at: ...STALLED_AFTER.ago) }
  end

  def stalled?
    in_progress? && updated_at < STALLED_AFTER.ago
  end
end
