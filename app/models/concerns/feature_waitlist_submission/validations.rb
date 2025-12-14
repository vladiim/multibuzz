# frozen_string_literal: true

module FeatureWaitlistSubmission::Validations
  extend ActiveSupport::Concern

  included do
    validates :feature_key, presence: true,
      inclusion: { in: FeatureWaitlistSubmission::VALID_FEATURES, message: "is not a valid feature" }
    validates :feature_name, presence: true
  end
end
