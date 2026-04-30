# frozen_string_literal: true

module AdPlatformConnection::Validations
  extend ActiveSupport::Concern

  MAX_SETTINGS_BYTES = 51_200
  MAX_METADATA_BYTES = 5_120

  included do
    validates :platform, presence: true
    validates :platform_account_id, presence: true
    validates :currency, presence: true, length: { maximum: 3 }
    validates :platform_account_id, uniqueness: { scope: [ :account_id, :platform ] }
    validate :settings_size_limit
    validate :metadata_shape_and_size
  end

  private

  def settings_size_limit
    return unless settings.is_a?(Hash) && settings.to_json.bytesize > MAX_SETTINGS_BYTES

    errors.add(:settings, "must be less than 50KB")
  end

  def metadata_shape_and_size
    return errors.add(:metadata, "must be a hash") unless metadata.is_a?(Hash)
    return if metadata.to_json.bytesize <= MAX_METADATA_BYTES

    errors.add(:metadata, "must be less than 5KB")
  end
end
