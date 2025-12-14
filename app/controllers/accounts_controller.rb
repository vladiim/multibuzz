# frozen_string_literal: true

class AccountsController < ApplicationController
  before_action :require_login

  def new
    @account = Account.new
  end

  def create
    creation_result[:success] ? redirect_to_new_account : render_errors
  end

  private

  def creation_result
    @creation_result ||= Accounts::CreationService.new(
      user: current_user,
      name: account_params[:name]
    ).call
  end

  def redirect_to_new_account
    redirect_to dashboard_path(account_id: creation_result[:account].prefix_id),
      notice: "Account created successfully!"
  end

  def render_errors
    @account = Account.new(account_params)
    @account.errors.add(:base, creation_result[:errors].join(", "))
    render :new, status: :unprocessable_entity
  end

  def account_params
    params.require(:account).permit(:name)
  end
end
