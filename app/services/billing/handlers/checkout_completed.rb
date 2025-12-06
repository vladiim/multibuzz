module Billing
  module Handlers
    class CheckoutCompleted < Base
      class PlanNotFoundError < StandardError; end

      private

      def handle_event
        validate_plan!
        activate_subscription
      end

      def validate_plan!
        return if plan.present?

        raise PlanNotFoundError, "Plan not found for slug: #{plan_slug.inspect}"
      end

      def activate_subscription
        account.update!(
          billing_status: :active,
          stripe_subscription_id: subscription_id,
          plan: plan,
          subscription_started_at: Time.current
        )
      end

      def subscription_id
        event_object[:subscription]
      end

      def plan
        @plan ||= Plan.find_by(slug: plan_slug)
      end

      def plan_slug
        metadata[:plan_slug]
      end

      def metadata
        event_object[:metadata] || {}
      end
    end
  end
end
