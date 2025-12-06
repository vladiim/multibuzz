module ContactSubmission::Validations
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
    validates :subject, presence: true,
      inclusion: { in: ContactSubmission::VALID_SUBJECTS, message: "%{value} is not a valid subject" }
    validates :message, presence: true
  end
end
