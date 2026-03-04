# frozen_string_literal: true

module IntegrationRequestSubmission::Validations
  extend ActiveSupport::Concern

  included do
    validates :platform_name, presence: true,
      inclusion: { in: IntegrationRequestSubmission::PLATFORM_OPTIONS, message: "%{value} is not a valid platform" }
    validates :platform_name_other, presence: true, if: -> { platform_name == "Other" }
    validates :monthly_spend, inclusion: { in: IntegrationRequestSubmission::MONTHLY_SPEND_OPTIONS }, allow_blank: true
  end
end
