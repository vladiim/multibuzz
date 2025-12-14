module User::AccountAccess
  extend ActiveSupport::Concern

  def member_of?(account)
    membership_for(account)&.accepted?
  end

  def admin_of?(account)
    membership = membership_for(account)
    membership&.accepted? && (membership.admin? || membership.owner?)
  end

  def owner_of?(account)
    membership_for(account)&.owner? && membership_for(account)&.accepted?
  end

  def role_for(account)
    membership_for(account)&.role
  end

  def membership_for(account)
    account_memberships.not_deleted.find_by(account: account)
  end

  def active_accounts
    accounts.joins(:account_memberships)
      .where(account_memberships: { user_id: id, status: :accepted, deleted_at: nil })
  end

  def active_memberships
    account_memberships.active.includes(:account).order(last_accessed_at: :desc, role: :desc)
  end

  def pending_invitations
    account_memberships.pending.not_deleted.includes(:account).order(created_at: :desc)
  end

  def primary_account
    account_memberships.active.order(last_accessed_at: :desc, role: :desc).first&.account
  end
end
