class OnboardingMailer < ApplicationMailer
  def welcome(account:, user:)
    @account = account
    @user = user
    @api_key = account.api_keys.test.first

    mail(
      to: user.email,
      subject: "Welcome to mbuzz - your API key is ready"
    )
  end
end
