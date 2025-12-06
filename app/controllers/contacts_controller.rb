class ContactsController < ApplicationController
  def new
    @submission = ContactSubmission.new
  end

  def create
    submission.save ? create_success : create_failure
  end

  def show
  end

  private

  def submission
    @submission ||= ContactSubmission.new(create_submission_params)
  end

  def create_submission_params
    submission_params.merge(
      ip_address: anonymized_ip,
      user_agent: request.user_agent
    )
  end

  def anonymized_ip
    IPAddr.new(request.remote_ip).mask(24).to_s
  rescue IPAddr::InvalidAddressError
    nil
  end

  def submission_params
    params
      .require(:contact_submission)
      .permit(:email, :name, :subject, :message)
  end

  def create_success
    redirect_to contact_thank_you_path, notice: t("contact.create.success")
  end

  def create_failure
    render :new, status: :unprocessable_entity
  end
end
