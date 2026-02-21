# frozen_string_literal: true

module Visitor::Scopes
  extend ActiveSupport::Concern

  included do
    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
    scope :recent, -> { where("last_seen_at >= ?", 30.days.ago).order(last_seen_at: :desc) }
  end
end
