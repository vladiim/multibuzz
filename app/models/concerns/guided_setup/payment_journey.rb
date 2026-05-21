# frozen_string_literal: true

module GuidedSetup::PaymentJourney
  extend ActiveSupport::Concern

  PAYMENT_TOKEN_TTL = 48.hours
  PAYMENT_TOKEN_BYTES = 32

  def book_kickoff!(scheduling_preferences:)
    update!(scheduling_preferences: scheduling_preferences, kickoff_booked_at: Time.current)
  end

  def mint_payment_token!(expires_in: PAYMENT_TOKEN_TTL)
    update!(
      payment_token: SecureRandom.urlsafe_base64(PAYMENT_TOKEN_BYTES),
      payment_token_expires_at: expires_in.from_now
    )
    payment_token
  end

  def clear_payment_token!
    update!(payment_token: nil, payment_token_expires_at: nil)
  end

  def payment_token_active?
    payment_token.present? && payment_token_expires_at.present? && payment_token_expires_at > Time.current
  end

  def awaiting_payment?
    pending? && payment_token_active?
  end

  class_methods do
    def find_by_active_payment_token(token)
      return if token.blank?

      where(payment_token: token).where("payment_token_expires_at > ?", Time.current).first
    end
  end
end
