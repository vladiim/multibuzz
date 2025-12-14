# frozen_string_literal: true

module ConversionPropertyKey::Scopes
  extend ActiveSupport::Concern

  RECENT_THRESHOLD = 30.days

  included do
    scope :by_popularity, -> { order(occurrences: :desc) }
    scope :recent, -> { where("last_seen_at > ?", RECENT_THRESHOLD.ago) }
  end
end
