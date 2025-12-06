class AccountController < ApplicationController
  before_action :require_login

  def show
  end

  def update
    current_account.update(account_params) ? redirect_to_success : render_errors
  end

  private

  def account_params
    params.require(:account).permit(:name, :billing_email)
  end

  def redirect_to_success
    redirect_to account_path, notice: t(".success")
  end

  def render_errors
    render :show, status: :unprocessable_entity
  end
end
