module Billing
  module Handlers
    class InvoicePaid < Base
      private

      def handle_event
        clear_past_due_status
        unlock_events_if_needed
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
    end
  end
end
