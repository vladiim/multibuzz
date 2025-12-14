# frozen_string_literal: true

module SetupGuidanceHelper
  SETUP_STEPS = %i[api_key events conversions users].freeze

  def setup_guidance_banner(account)
    return nil unless account

    SETUP_STEPS.find { |step| !send("#{step}_setup_complete?", account) }
  end

  # Step completion checks
  def api_key_setup_complete?(account)
    account.api_keys.live.active.exists?
  end

  def events_setup_complete?(account)
    account.events.production.exists?
  end

  def conversions_setup_complete?(account)
    account.conversions.production.exists?
  end

  def users_setup_complete?(account)
    account.identities.production.exists?
  end
end
