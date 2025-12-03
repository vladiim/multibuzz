module Dashboard
  class BillingController < BaseController
    def checkout
      return redirect_with_error(checkout_result[:errors].first) unless checkout_result[:success]

      redirect_to checkout_result[:checkout_url], allow_other_host: true
    end

    def portal
      return redirect_with_error(portal_result[:errors].first) unless portal_result[:success]

      redirect_to portal_result[:portal_url], allow_other_host: true
    end

    def success
      @session_id = params[:session_id]
    end

    def cancel
      redirect_to dashboard_path, notice: "Checkout cancelled"
    end

    private

    def checkout_result
      @checkout_result ||= Billing::CheckoutService.new(
        account: current_account,
        plan_slug: params[:plan_slug],
        user: current_user,
        success_url: dashboard_billing_success_url(session_id: "{CHECKOUT_SESSION_ID}"),
        cancel_url: dashboard_billing_cancel_url
      ).call
    end

    def portal_result
      @portal_result ||= Billing::PortalService.new(
        account: current_account,
        return_url: dashboard_url
      ).call
    end

    def redirect_with_error(message)
      redirect_to dashboard_path, alert: message
    end
  end
end
