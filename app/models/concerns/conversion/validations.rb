# frozen_string_literal: true

module Conversion::Validations
  extend ActiveSupport::Concern

  included do
    validates :conversion_type, presence: true
    validates :converted_at, presence: true
    validates :revenue,
      numericality: { greater_than_or_equal_to: 0 },
      allow_nil: true

    validate :identity_required_for_acquisition
  end

  private

  def identity_required_for_acquisition
    return unless is_acquisition? && identity_id.blank?

    errors.add(:identity, "is required when marking as acquisition")
  end
end
