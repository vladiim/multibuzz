# frozen_string_literal: true

class InvitationsController < ApplicationController
  SHOW_ERROR_HANDLERS = {
    not_found: :render_not_found,
    expired: :render_expired,
    already_accepted: :render_already_accepted
  }.freeze

  CREATE_ERROR_HANDLERS = {
    not_found: :render_not_found,
    expired: :render_expired,
    wrong_user: :render_wrong_user,
    validation_error: :render_validation_errors
  }.freeze

  def show
    handler = SHOW_ERROR_HANDLERS[lookup_result[:error_code]]
    handler ? send(handler) : render_acceptance_form
  end

  def create
    handler = CREATE_ERROR_HANDLERS[acceptance_result[:error_code]]
    handler ? send(handler) : complete_acceptance
  end

  def accept_pending
    return redirect_to login_path, alert: "Please log in to accept invitation" unless current_user

    pending_acceptance_result[:success] ? complete_pending_acceptance : redirect_with_error
  end

  private

  def pending_acceptance_result
    @pending_acceptance_result ||= pending_membership&.pending? ? accept_pending_membership : { success: false }
  end

  def pending_membership
    @pending_membership ||= current_user.account_memberships.pending.not_deleted.find_by_prefix_id(params[:id])
  end

  def accept_pending_membership
    pending_membership.update!(status: :accepted, accepted_at: Time.current, invitation_token_digest: nil)
    { success: true }
  end

  def complete_pending_acceptance
    redirect_to dashboard_path(account_id: pending_membership.account.prefix_id), notice: "Welcome to #{pending_membership.account.name}!"
  end

  def redirect_with_error
    redirect_to dashboard_path, alert: "Could not accept invitation"
  end

  def lookup_result
    @lookup_result ||= acceptance_service(lookup_only: true).call
  end

  def acceptance_result
    @acceptance_result ||= acceptance_service.call
  end

  def acceptance_service(lookup_only: false)
    Team::AcceptanceService.new(
      token: params[:token],
      current_user: current_user,
      password: params[:password],
      password_confirmation: params[:password_confirmation],
      lookup_only: lookup_only
    )
  end

  def render_acceptance_form
    @membership = lookup_result[:membership]
    @account = @membership.account
    render :show
  end

  def complete_acceptance
    membership = acceptance_result[:membership]
    sign_in(membership.user) unless current_user
    redirect_to dashboard_path, notice: "Welcome to #{membership.account.name}!"
  end

  def sign_in(user)
    session[:user_id] = user.id
  end

  def render_not_found
    render :not_found, status: :not_found
  end

  def render_expired
    render :expired, status: :gone
  end

  def render_already_accepted
    render :already_accepted, status: :gone
  end

  def render_wrong_user
    @membership = lookup_result[:membership]
    render :wrong_user, status: :forbidden
  end

  def render_validation_errors
    @membership = lookup_result[:membership]
    @account = @membership.account
    @errors = acceptance_result[:errors]
    render :show, status: :unprocessable_entity
  end
end
