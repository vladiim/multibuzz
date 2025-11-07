module Visitor::Scopes
  extend ActiveSupport::Concern

  included do
    scope :recent, -> { where("last_seen_at >= ?", 30.days.ago).order(last_seen_at: :desc) }
  end
end
