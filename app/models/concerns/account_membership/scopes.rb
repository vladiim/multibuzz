module AccountMembership::Scopes
  extend ActiveSupport::Concern

  included do
    scope :active, -> { accepted.where(deleted_at: nil) }
    scope :not_deleted, -> { where(deleted_at: nil) }
    scope :deleted, -> { where.not(deleted_at: nil) }
  end
end
