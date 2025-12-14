# frozen_string_literal: true

class FeatureWaitlistController < ApplicationController
  def create
    return handle_missing_email unless email_present?
    return handle_duplicate if already_on_waitlist?
    return handle_validation_error unless submission.save

    redirect_back fallback_location: root_path,
      notice: "You've been added to the #{submission.feature_name} waitlist!"
  end

  private

  def submission
    @submission ||= FeatureWaitlistSubmission.new(submission_params)
  end

  def submission_params
    {
      email: submission_email,
      feature_key: params[:feature_key],
      feature_name: params[:feature_name],
      context: params[:context],
      ip_address: anonymized_ip,
      user_agent: request.user_agent
    }
  end

  def submission_email
    logged_in? ? current_user.email : params[:email]
  end

  def email_present?
    submission_email.present?
  end

  def already_on_waitlist?
    return false unless params[:feature_key].present?

    FeatureWaitlistSubmission
      .where(email: submission_email)
      .where("data->>'feature_key' = ?", params[:feature_key])
      .exists?
  end

  def handle_missing_email
    redirect_back fallback_location: root_path,
      alert: "Email is required to join the waitlist."
  end

  def handle_duplicate
    redirect_back fallback_location: root_path,
      notice: "You're already on the waitlist for this feature!"
  end

  def handle_validation_error
    error_message = submission.errors.full_messages.first || "Invalid feature"
    redirect_back fallback_location: root_path, alert: error_message
  end

  def anonymized_ip
    IPAddr.new(request.remote_ip).mask(24).to_s
  rescue IPAddr::InvalidAddressError
    nil
  end
end
