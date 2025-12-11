# frozen_string_literal: true

class FeatureWaitlistSubmission < FormSubmission
  VALID_FEATURES = %w[data_export csv_export api_extract].freeze

  store_accessor :data, :feature_key, :feature_name, :context

  include FeatureWaitlistSubmission::Validations
end
