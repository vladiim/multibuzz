# frozen_string_literal: true

class Export < ApplicationRecord
  EXPORT_TYPES = %w[conversions funnel].freeze
  EXPIRY_DURATION = 1.hour

  belongs_to :account

  has_prefix_id :exp

  enum :status, { pending: 0, processing: 1, completed: 2, failed: 3 }

  validates :export_type, presence: true, inclusion: { in: EXPORT_TYPES }

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def cleanup!
    File.delete(file_path) if file_path.present? && File.exist?(file_path)
    destroy!
  end
end
