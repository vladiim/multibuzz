module ApiKey::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { where(revoked_at: nil) }
    scope :revoked, -> { where.not(revoked_at: nil) }
  end
end
