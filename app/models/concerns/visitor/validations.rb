# frozen_string_literal: true

module Visitor::Validations
  extend ActiveSupport::Concern

  ID_FORMAT = /\A[a-zA-Z0-9._:\-]{1,}\z/
  ID_FORMAT_MESSAGE = "must contain only letters, numbers, underscores, hyphens, dots, and colons"
  MAX_JSONB_BYTES = 50.kilobytes

  included do
    validates :visitor_id,
      presence: true,
      uniqueness: { scope: :account_id },
      length: { maximum: 255 },
      format: { with: ID_FORMAT, message: ID_FORMAT_MESSAGE }

    validate :traits_size_limit
  end

  private

  def traits_size_limit
    return unless traits.is_a?(Hash)
    return if traits.to_json.bytesize <= MAX_JSONB_BYTES

    errors.add(:traits, "exceeds maximum size of #{MAX_JSONB_BYTES} bytes")
  end
end
