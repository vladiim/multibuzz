# frozen_string_literal: true

module Billing
  module Handlers
    class InvoicePaymentFailed < Base
      private

      def handle_event
        return if already_past_due?

        mark_past_due
        track_payment_failed
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

      def track_payment_failed
        Lifecycle::Tracker.track(
          "billing_payment_failed",
          account,
          plan: account.plan&.slug,
          grace_period_ends_at: account.grace_period_ends_at&.iso8601
        )
      end
    end
  end
end
