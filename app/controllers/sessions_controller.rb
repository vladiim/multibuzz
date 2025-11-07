class SessionsController < ApplicationController
  def new
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
    redirect_to dashboard_path, notice: "Logged in successfully"
  end

  def login_failure
    flash.now[:alert] = "Invalid email or password"
    render :new, status: :unprocessable_entity
  end
end
