# frozen_string_literal: true

module AdPlatformConnection::Validations
  extend ActiveSupport::Concern

  MAX_SETTINGS_BYTES = 51_200

  included do
    validates :platform, presence: true
    validates :platform_account_id, presence: true
    validates :currency, presence: true, length: { maximum: 3 }
    validates :platform_account_id, uniqueness: { scope: [ :account_id, :platform ] }
    validate :settings_size_limit
  end

  private

  def settings_size_limit
    return unless settings.is_a?(Hash) && settings.to_json.bytesize > MAX_SETTINGS_BYTES

    errors.add(:settings, "must be less than 50KB")
  end
end
