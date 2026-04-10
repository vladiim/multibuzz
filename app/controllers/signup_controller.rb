# frozen_string_literal: true

class SignupController < ApplicationController
  def new
    @user = User.new
    @account = Account.new
  end

  def create
    signup_successful? ? handle_success : handle_failure
  end

  def welcome
    return redirect_to signup_path unless current_user
    @user_id_hashed = Digest::SHA256.hexdigest(current_user.email.downcase.strip)
  end

  private

  def signup_successful?
    signup_result[:success]
  end

  def handle_success
    log_in_user
    track_signup
    redirect_to signup_welcome_path
  end

  def handle_failure
    @user = User.new(user_params.except(:password))
    @account = Account.new(account_params)
    signup_result[:errors].each { |e| @user.errors.add(:base, e) }
    render :new, status: :unprocessable_entity
  end

  def track_signup
    user = signup_result[:user]
    account = signup_result[:account]
    Mbuzz.identify(user.prefix_id, traits: { email: user.email, account_name: account.name })
    Mbuzz.conversion("signup", user_id: user.prefix_id, is_acquisition: true, account_name: account.name)
  end

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

  def user_params
    params.require(:user).permit(:email, :password)
  end

  def account_params
    params.require(:account).permit(:name)
  end
end
