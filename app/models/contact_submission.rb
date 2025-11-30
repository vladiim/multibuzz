class ContactSubmission < FormSubmission
  VALID_SUBJECTS = %w[general sales support partnership other].freeze

  store_accessor :data, :name, :subject, :message

  include ContactSubmission::Validations
end
