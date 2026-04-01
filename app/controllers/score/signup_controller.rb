# frozen_string_literal: true

module Score
  class SignupController < ApplicationController
    layout "score"

    before_action :redirect_if_logged_in

    def new
      @user = User.new
      @claim_token = params[:claim_token]
    end

    def create
      signup_successful? ? handle_success : handle_failure
    end

    private

    def redirect_if_logged_in
      redirect_to score_dashboard_path if logged_in?
    end

    def signup_successful?
      signup_result[:success]
    end

    def handle_success
      session[:user_id] = signup_result[:user].id
      redirect_to score_dashboard_path
    end

    def handle_failure
      @user = User.new(email: user_params[:email])
      @company_name = user_params[:company_name]
      @claim_token = params[:claim_token]
      signup_result[:errors].each { |e| @user.errors.add(:base, e) }
      render :new, status: :unprocessable_entity
    end

    def signup_result
      @signup_result ||= Score::SignupService.new(
        email: user_params[:email],
        password: user_params[:password],
        company_name: user_params[:company_name],
        claim_token: params[:claim_token]
      ).call
    end

    def user_params
      params.require(:user).permit(:email, :password, :company_name)
    end
  end
end
