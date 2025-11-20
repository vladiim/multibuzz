class Conversion < ApplicationRecord
  include Conversion::Relationships
  include Conversion::Validations

  has_prefix_id :conv

  # conversion_type is a flexible string - users define their own
  # Examples: "signup", "purchase", "trial_start", "demo_request", etc.
  # No enum - user-defined conversion types
end
