class FormSubmission < ApplicationRecord
  include FormSubmission::Validations
  include FormSubmission::Scopes

  has_prefix_id :form

  enum :status, { pending: 0, contacted: 1, completed: 2, spam: 3 }

  store_accessor :data

  after_create_commit :send_notification_email

  private

  def send_notification_email
    FormSubmissionMailer.notify(self).deliver_later
  end
end
