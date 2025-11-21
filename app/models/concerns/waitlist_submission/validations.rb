module WaitlistSubmission::Validations
  extend ActiveSupport::Concern

  included do
    validates :role, presence: true,
      inclusion: { in: WaitlistSubmission::VALID_ROLES, message: "%{value} is not a valid role" }
    validates :framework, presence: true,
      inclusion: { in: WaitlistSubmission::VALID_FRAMEWORKS, message: "%{value} is not a valid framework" }
    validates :framework_other, presence: true, if: -> { framework == "other" }
  end
end
