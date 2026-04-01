# frozen_string_literal: true

class SessionsController < ApplicationController
  before_action :redirect_if_logged_in, only: :new

  def new
    session[:return_to] = params[:return_to] if params[:return_to].present?
    session[:score_claim_token] = params[:claim_token] if params[:claim_token].present?
  end

  def create
    login? ? login_success : login_failure
  end

  def destroy
    session[:user_id] = nil
    redirect_to login_path, notice: "Logged out successfully"
  end

  private

  def login?
    user&.authenticate(params[:password])
  end

  def user
    @user ||= User.find_by(email: params[:email])
  end

  def login_success
    session[:user_id] = user.id
    track_login
    claim_score_assessment
    redirect_to post_login_path, notice: "Logged in successfully"
  end

  def track_login
    Mbuzz.identify(user.prefix_id, traits: { email: user.email })
    Mbuzz.event("login")
  end

  def login_failure
    flash.now[:alert] = "Invalid email or password"
    render :new, status: :unprocessable_entity
  end

  def redirect_if_logged_in
    return unless logged_in?

    destination = params[:return_to]&.start_with?("/") ? params[:return_to] : dashboard_path
    redirect_to destination
  end

  def claim_score_assessment
    token = session.delete(:score_claim_token)
    return unless token

    assessment = ScoreAssessment.find_by(claim_token: token)
    assessment&.update!(user: user, claim_token: nil)
  end

  def post_login_path
    path = session.delete(:return_to)
    return path if path&.start_with?("/")

    dashboard_path
  end
end
