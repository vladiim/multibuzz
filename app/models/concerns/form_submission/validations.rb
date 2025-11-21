module FormSubmission::Validations
  extend ActiveSupport::Concern

  included do
    validates :email, presence: true,
      format: { with: URI::MailTo::EMAIL_REGEXP, message: "must be a valid email address" }
    validates :type, presence: true
  end
end
