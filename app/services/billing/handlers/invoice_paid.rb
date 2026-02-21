# frozen_string_literal: true

module Billing
  module Handlers
    class InvoicePaid < Base
      private

      def handle_event
        clear_past_due_status
        unlock_events_if_needed
        track_payment
      end

      def clear_past_due_status
        return unless account.billing_past_due?

        account.update!(
          billing_status: :active,
          payment_failed_at: nil,
          grace_period_ends_at: nil
        )
      end

      def unlock_events_if_needed
        return unless had_locked_events?

        Billing::UnlockEventsService.new(account).call
      end

      def had_locked_events?
        account.events.where(locked: true).exists?
      end

      def track_payment
        return unless owner

        Mbuzz.conversion(
          "payment",
          user_id: owner.prefix_id,
          revenue: amount_in_dollars,
          inherit_acquisition: true,
          invoice_id: event_object[:id],
          account_name: account.name
        )
      end

      def owner
        @owner ||= account.account_memberships.owner.accepted.first&.user
      end

      def amount_in_dollars
        (event_object[:amount_paid] || 0) / 100.0
      end
    end
  end
end
