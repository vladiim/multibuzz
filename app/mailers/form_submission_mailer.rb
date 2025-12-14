# frozen_string_literal: true

class FormSubmissionMailer < ApplicationMailer
  NOTIFICATION_EMAIL = "vlad@forebrite.com"

  def notify(submission)
    @submission = submission

    mail(
      to: NOTIFICATION_EMAIL,
      subject: subject_for(submission)
    )
  end

  private

  def subject_for(submission)
    case submission
    when ContactSubmission
      "[mbuzz Contact] #{submission.subject} from #{submission.name}"
    when WaitlistSubmission
      "[mbuzz Waitlist] New signup from #{submission.email}"
    when SdkWaitlistSubmission
      "[mbuzz SDK Waitlist] #{submission.sdk_name} interest from #{submission.email}"
    when FeatureWaitlistSubmission
      "[mbuzz Feature Waitlist] #{submission.feature_name} interest from #{submission.email}"
    else
      "[mbuzz] New form submission"
    end
  end
end
