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
end
