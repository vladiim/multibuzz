# frozen_string_literal: true

class AccountController < ApplicationController
  before_action :require_login

  def show
  end

  def update
    if current_account.update(account_params)
      clear_view_mode_if_live_mode_enabled
      redirect_to_success
    else
      render_errors
    end
  end

  private

  def account_params
    params.require(:account).permit(:name, :billing_email, :live_mode_enabled)
  end

  def redirect_to_success
    redirect_to account_path, notice: success_message
  end

  def success_message
    return live_mode_message if live_mode_changed?

    t(".success")
  end

  def live_mode_changed?
    params.dig(:account, :live_mode_enabled).present?
  end

  def clear_view_mode_if_live_mode_enabled
    return unless current_account.live_mode_enabled?

    session.delete(:view_mode)
  end

  def live_mode_message
    if current_account.live_mode_enabled?
      "Live mode enabled. Dashboard now shows production data."
    else
      "Test mode enabled. Dashboard now shows test data."
    end
  end

  def render_errors
    render :show, status: :unprocessable_entity
  end
end
