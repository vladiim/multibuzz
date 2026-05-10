# frozen_string_literal: true

module Conversion::Validations
  extend ActiveSupport::Concern

  MAX_JSONB_BYTES = 50.kilobytes
  RESERVED_PROPERTY_KEYS = %w[url referrer].freeze

  included do
    validates :conversion_type, presence: true
    validates :converted_at, presence: true
    validates :revenue,
      numericality: { greater_than_or_equal_to: 0 },
      allow_nil: true

    validate :identity_required_for_acquisition
    validate :properties_size_limit
  end

  private

  def identity_required_for_acquisition
    return unless is_acquisition? && identity_id.blank?

    errors.add(:identity, "is required when marking as acquisition")
  end

  def properties_size_limit
    return unless properties.is_a?(Hash)
    return if properties.to_json.bytesize <= MAX_JSONB_BYTES

    errors.add(:properties, "exceeds maximum size of #{MAX_JSONB_BYTES} bytes")
  end
end
