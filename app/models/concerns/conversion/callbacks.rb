# frozen_string_literal: true

module Conversion::Callbacks
  extend ActiveSupport::Concern

  included do
    after_create_commit :queue_attribution_calculation
    after_create_commit :queue_property_key_discovery, if: :has_properties?
    after_create_commit :broadcast_to_onboarding, if: :should_broadcast_to_onboarding?
    after_create_commit :broadcast_to_feed
  end

  private

  def queue_attribution_calculation
    Conversions::AttributionCalculationJob.perform_later(id)
  end

  def queue_property_key_discovery
    Conversions::PropertyKeyDiscoveryJob.perform_later(account_id)
  end

  def has_properties?
    properties.present? && properties != {}
  end

  def broadcast_to_onboarding
    account.complete_onboarding_step!(:first_conversion)
    broadcast_replace_to(
      "onboarding_#{account.prefix_id}",
      target: "conversion_status",
      partial: "onboarding/conversion_received"
    )
  end

  def should_broadcast_to_onboarding?
    !account.onboarding_step_completed?(:first_conversion)
  end

  def broadcast_to_feed
    feed_item = FeedItem.new(feed_type: :conversion, occurred_at: converted_at, record: self)
    broadcast_prepend_to(
      "account_#{account.prefix_id}_events",
      target: "events-list",
      partial: "dashboard/live_events/feed_item",
      locals: { feed_item: feed_item }
    )
  end
end
