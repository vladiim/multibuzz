# frozen_string_literal: true

module Billing
  module Handlers
    class SubscriptionDeleted < Base
      private

      def handle_event
        cancel_subscription
      end

      def cancel_subscription
        account.update!(
          billing_status: :cancelled,
          stripe_subscription_id: nil
        )
      end
    end
  end
end
