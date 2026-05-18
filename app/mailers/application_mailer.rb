# frozen_string_literal: true

class ApplicationMailer < ActionMailer::Base
  default from: "mbuzz <hello@mbuzz.co>"
  layout "mailer"

  private

  def internal_notification_email
    Rails.application.credentials.dig(:notifications, :internal_email)
  end
end
