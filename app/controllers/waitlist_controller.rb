class WaitlistController < ApplicationController
  def new
    @submission = WaitlistSubmission.new
  end

  def create
    submission.save ? create_success : create_failure
  end

  def show
    @submission = WaitlistSubmission.find(params[:id])
  end

  private

  def submission
    @submission ||= WaitlistSubmission.new(create_submission_params)
  end

  def create_submission_params
    submission_params.merge(
      ip_address: request.remote_ip,
      user_agent: request.user_agent
    )
  end

  def submission_params
    params
      .require(:waitlist_submission)
      .permit(:email, :role, :framework, :framework_other)
  end

  def create_success
    redirect_to waitlist_path(submission),
      notice: t("waitlist.create.success")
  end

  def create_failure
    render :new, status: :unprocessable_entity
  end
end
