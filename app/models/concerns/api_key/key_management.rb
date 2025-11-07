module ApiKey::KeyManagement
  extend ActiveSupport::Concern

  def active?
    revoked_at.nil?
  end

  def revoked?
    revoked_at.present?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  def record_usage!
    update_column(:last_used_at, Time.current)
  end

  def masked_key
    "#{key_prefix}••••••••••••••••••••"
  end
end
