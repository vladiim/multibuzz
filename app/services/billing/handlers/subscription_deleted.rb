# frozen_string_literal: true

module Billing
  module Handlers
    class SubscriptionDeleted < Base
      private

      def handle_event
        cancel_subscription
        track_cancelled
      end

      def cancel_subscription
        account.update!(
          billing_status: :cancelled,
          stripe_subscription_id: nil,
          subscription_cancelled_at: Time.current
        )
      end

      def track_cancelled
        Lifecycle::Tracker.track(
          "billing_cancelled",
          account,
          plan: account.plan&.slug,
          days_as_customer: days_as_customer,
          lifetime_value_cents: account.lifetime_value_cents
        )
      end

      def days_as_customer
        return nil unless account.subscription_started_at

        ((Time.current - account.subscription_started_at) / 1.day).round
      end
    end
  end
end
