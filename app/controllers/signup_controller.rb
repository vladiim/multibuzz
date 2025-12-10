# frozen_string_literal: true

class SignupController < ApplicationController
  def new
    @user = User.new
    @account = Account.new
  end

  def create
    if signup_result[:success]
      log_in_user
      redirect_to onboarding_path
    else
      render_errors
    end
  end

  private

  def signup_result
    @signup_result ||= SignupService.new(
      email: user_params[:email],
      password: user_params[:password],
      account_name: account_params[:name]
    ).call
  end

  def log_in_user
    session[:user_id] = signup_result[:user].id
    session[:plaintext_api_key] = signup_result[:plaintext_api_key]
  end

  def render_errors
    @user = User.new(user_params.except(:password))
    @account = Account.new(account_params)
    signup_result[:errors].each { |e| @user.errors.add(:base, e) }
    render :new, status: :unprocessable_entity
  end

  def user_params
    params.require(:user).permit(:email, :password)
  end

  def account_params
    params.require(:account).permit(:name)
  end
end
