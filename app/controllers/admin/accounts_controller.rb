# frozen_string_literal: true

module Admin
  class AccountsController < BaseController
    def show
      @account = find_account
      @plans = Plan.active.sorted
    end

    def update
      @account = find_account

      if update_free_until
        redirect_to admin_account_path(@account), notice: "Account updated successfully."
      else
        @plans = Plan.active.sorted
        render :show, status: :unprocessable_entity
      end
    end

    private

    def find_account
      Account.find(params[:id])
    end

    def update_free_until
      if account_params[:free_until].blank?
        clear_free_until
      else
        grant_free_until
      end
    end

    def grant_free_until
      @account.grant_free_until!(
        until_date: account_params[:free_until],
        plan: find_plan
      )
    end

    def clear_free_until
      @account.update!(
        billing_status: :free_forever,
        free_until: nil
      )
    end

    def find_plan
      return @account.plan unless account_params[:plan_id].present?

      Plan.find(account_params[:plan_id])
    end

    def account_params
      params.require(:account).permit(:free_until, :plan_id)
    end
  end
end
