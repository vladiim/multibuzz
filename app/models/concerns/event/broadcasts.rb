# frozen_string_literal: true

module Event::Broadcasts
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_to_account
    after_create_commit :broadcast_to_onboarding, if: :should_broadcast_to_onboarding?
  end

  private

  def broadcast_to_account
    broadcast_prepend_to(
      "account_#{account.prefix_id}_events",
      target: "events-list",
      partial: "dashboard/live_events/event_card",
      locals: { event: self }
    )
  end

  def broadcast_to_onboarding
    account.complete_onboarding_step!(:first_event_received)
    broadcast_replace_to(
      "onboarding_#{account.prefix_id}",
      target: "verification_status",
      partial: "onboarding/event_received"
    )
  end

  def should_broadcast_to_onboarding?
    !account.onboarding_step_completed?(:first_event_received)
  end
end
