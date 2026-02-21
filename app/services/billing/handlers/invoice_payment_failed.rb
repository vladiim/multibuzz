# frozen_string_literal: true

module Billing
  module Handlers
    class InvoicePaymentFailed < Base
      private

      def handle_event
        return if already_past_due?

        mark_past_due
      end

      def already_past_due?
        account.billing_past_due?
      end

      def mark_past_due
        account.update!(
          billing_status: :past_due,
          payment_failed_at: Time.current,
          grace_period_ends_at: Billing::GRACE_PERIOD_DAYS.days.from_now
        )
      end
    end
  end
end
