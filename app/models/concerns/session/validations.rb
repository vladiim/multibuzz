module Session::Validations
  extend ActiveSupport::Concern

  MAX_JSONB_BYTES = 50.kilobytes

  included do
    validates :session_id,
      presence: true,
      uniqueness: { scope: :account_id }

    validate :initial_utm_size_limit
  end

  private

  def initial_utm_size_limit
    return unless initial_utm.is_a?(Hash)
    return if initial_utm.to_json.bytesize <= MAX_JSONB_BYTES

    errors.add(:initial_utm, "exceeds maximum size of #{MAX_JSONB_BYTES} bytes")
  end
end
