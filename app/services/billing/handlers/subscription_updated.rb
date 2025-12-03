module Billing
  module Handlers
    class SubscriptionUpdated < Base
      private

      def handle_event
        sync_subscription_details
      end

      def sync_subscription_details
        account.update!(
          stripe_subscription_id: subscription_id,
          current_period_start: period_start,
          current_period_end: period_end,
          billing_status: billing_status_from_stripe
        )
      end

      def subscription_id
        event_object[:id]
      end

      def period_start
        timestamp_to_time(event_object[:current_period_start])
      end

      def period_end
        timestamp_to_time(event_object[:current_period_end])
      end

      def billing_status_from_stripe
        Billing::STRIPE_STATUS_MAP.fetch(stripe_status) { account.billing_status }
      end

      def stripe_status
        event_object[:status]
      end

      def timestamp_to_time(timestamp)
        return nil unless timestamp

        Time.zone.at(timestamp)
      end
    end
  end
end
