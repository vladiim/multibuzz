module AccountMembership::Validations
  extend ActiveSupport::Concern

  included do
    validates :role, presence: true
    validates :status, presence: true
    validate :account_must_have_owner, if: :removing_owner?
  end

  private

  def removing_owner?
    return false unless role_was == "owner"

    revoked? || declined? || deleted_at.present?
  end

  def account_must_have_owner
    other_owners = account.account_memberships.owner.active.where.not(id: id)
    errors.add(:base, "account must have at least one owner") if other_owners.none?
  end
end
