class TeamMailer < ApplicationMailer
  def invitation(membership:, token:)
    @membership = membership
    @token = token
    @account = membership.account
    @inviter_email = membership.invited_by_email

    mail(
      to: membership.user.email,
      subject: "You've been invited to join #{@account.name} on mbuzz"
    )
  end

  def role_changed(membership:, old_role:)
    @membership = membership
    @old_role = old_role
    @account = membership.account

    mail(
      to: membership.user.email,
      subject: "Your role has been updated on #{@account.name}"
    )
  end

  def removed(email:, account:)
    @account = account

    mail(
      to: email,
      subject: "You've been removed from #{@account.name}"
    )
  end

  def ownership_transferred_to_new_owner(account:, new_owner:, previous_owner:)
    @account = account
    @new_owner = new_owner
    @previous_owner = previous_owner

    mail(
      to: new_owner.email,
      subject: "You are now the owner of #{account.name}"
    )
  end

  def ownership_transferred_to_previous_owner(account:, new_owner:, previous_owner:)
    @account = account
    @new_owner = new_owner
    @previous_owner = previous_owner

    mail(
      to: previous_owner.email,
      subject: "Ownership of #{account.name} has been transferred"
    )
  end
end
