# frozen_string_literal: true

module Event::Broadcasts
  extend ActiveSupport::Concern

  included do
    after_create_commit :broadcast_to_account
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
end
