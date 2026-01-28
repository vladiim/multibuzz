# frozen_string_literal: true

module Event::Broadcasts
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_to_account
    after_create_commit :broadcast_to_onboarding, if: :should_broadcast_to_onboarding?
    after_create_commit :track_first_event_for_dogfooding
  end

  private

  def broadcast_to_account
    feed_item = FeedItem.new(feed_type: :event, occurred_at: occurred_at, record: self)
    broadcast_prepend_to(
      "account_#{account.prefix_id}_events",
      target: "events-list",
      partial: "dashboard/live_events/feed_item",
      locals: { feed_item: feed_item }
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

  def track_first_event_for_dogfooding
    return unless first_event_of_type?

    owner = account.account_memberships.owner.accepted.first&.user
    return unless owner

    event_name = is_test ? "first_test_event" : "first_production_event"
    Mbuzz.event(event_name, user_id: owner.prefix_id, account_id: account.prefix_id, account_name: account.name)
  end

  def first_event_of_type?
    account.events.where(is_test: is_test).count == 1
  end
end
