# frozen_string_literal: true

module Event::Validations
  extend ActiveSupport::Concern

  MAX_JSONB_BYTES = 50.kilobytes

  included do
    validates :event_type, presence: true
    validates :occurred_at, presence: true
    validates :properties, presence: true

    validate :properties_must_be_hash
    validate :properties_size_limit
  end

  private

  def properties_must_be_hash
    return if properties.is_a?(Hash)

    errors.add(:properties, "must be a hash")
  end

  def properties_size_limit
    return unless properties.is_a?(Hash)
    return if properties.to_json.bytesize <= MAX_JSONB_BYTES

    errors.add(:properties, "exceeds maximum size of #{MAX_JSONB_BYTES} bytes")
  end
end
