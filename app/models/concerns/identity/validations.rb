# frozen_string_literal: true

module Identity::Validations
  extend ActiveSupport::Concern

  MAX_JSONB_BYTES = 50.kilobytes

  included do
    validates :external_id, presence: true
    validates :external_id, uniqueness: { scope: :account_id }
    validates :first_identified_at, presence: true
    validates :last_identified_at, presence: true

    validate :traits_size_limit
  end

  private

  def traits_size_limit
    return unless traits.is_a?(Hash)
    return if traits.to_json.bytesize <= MAX_JSONB_BYTES

    errors.add(:traits, "exceeds maximum size of #{MAX_JSONB_BYTES} bytes")
  end
end
