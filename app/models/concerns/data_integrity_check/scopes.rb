# frozen_string_literal: true

module DataIntegrityCheck::Scopes
  extend ActiveSupport::Concern

  included do
    scope :recent, -> { where("created_at >= ?", 24.hours.ago).order(created_at: :desc) }
    scope :by_check, ->(name) { where(check_name: name) }
    scope :worst_first, -> { order(Arel.sql("CASE status WHEN 'critical' THEN 0 WHEN 'warning' THEN 1 ELSE 2 END")) }
  end
end
