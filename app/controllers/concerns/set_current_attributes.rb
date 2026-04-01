# frozen_string_literal: true

# Sets Current.user and Current.account from session
#
# Include in ApplicationController to make Current attributes
# available throughout the request lifecycle.
#
# Usage:
#   class ApplicationController < ActionController::Base
#     include SetCurrentAttributes
#   end
#
#   # Then anywhere in the app:
#   Current.user    # => current user or nil
#   Current.account # => current account or nil
#
module SetCurrentAttributes
  extend ActiveSupport::Concern

  included do
    before_action :set_current_attributes
    helper_method :current_user, :current_account, :logged_in?
  end

  private

  def set_current_attributes
    Current.user = find_current_user
    Current.account = find_current_account
    update_last_accessed_at
  end

  def find_current_user
    return unless session[:user_id]

    User.find_by(id: session[:user_id])
  end

  def find_current_account
    return unless Current.user

    if params[:account_id].present?
      Current.user.active_accounts.find_by_prefix_id(params[:account_id])
    end || Current.user.primary_account
  end

  def current_user
    Current.user
  end

  def current_account
    Current.account
  end

  def logged_in?
    Current.user.present?
  end

  def require_login
    return if logged_in?

    session[:return_to] = request.fullpath
    redirect_to login_path, alert: "Please log in to continue"
  end

  def update_last_accessed_at
    return unless Current.user && Current.account

    Current.user.membership_for(Current.account)&.touch(:last_accessed_at)
  end
end
