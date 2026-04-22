# frozen_string_literal: true

module Billing
  module Handlers
    class InvoicePaid < Base
      private

      def handle_event
        recover_from_past_due if account.billing_past_due?
        increment_lifetime_value
        track_payment
      end

      def recover_from_past_due
        clear_past_due_status
        unlock_events_if_needed
        track_payment_recovered
      end

      def clear_past_due_status
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

      def increment_lifetime_value
        return if amount_in_cents.zero?

        account.update!(lifetime_value_cents: account.lifetime_value_cents + amount_in_cents)
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

      def track_payment_recovered
        Lifecycle::Tracker.track("billing_payment_recovered", account, plan: account.plan&.slug, invoice_id: event_object[:id])
      end

      def owner
        @owner ||= account.account_memberships.owner.accepted.first&.user
      end

      def amount_in_cents
        event_object[:amount_paid].to_i
      end

      def amount_in_dollars
        amount_in_cents / ::Billing::CENTS_PER_DOLLAR.to_f
      end
    end
  end
end
