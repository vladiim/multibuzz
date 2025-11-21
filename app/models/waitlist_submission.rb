class WaitlistSubmission < FormSubmission
  VALID_ROLES = %w[developer founder product_manager other].freeze
  VALID_FRAMEWORKS = %w[rails django laravel other].freeze

  store_accessor :data, :role, :framework, :framework_other

  include WaitlistSubmission::Validations
end
