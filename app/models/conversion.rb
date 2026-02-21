# frozen_string_literal: true

class Conversion < ApplicationRecord
  include Conversion::Relationships
  include Conversion::Validations
  include Conversion::Scopes
  include Conversion::Callbacks

  has_prefix_id :conv

  # conversion_type is a flexible string - users define their own
  # Examples: "signup", "purchase", "trial_start", "demo_request", etc.
  # No enum - user-defined conversion types

  # Transient attribute for attribution inheritance
  # When true, inherits attribution from user's acquisition conversion
  attr_accessor :inherit_acquisition

  def inherit_acquisition?
    ActiveModel::Type::Boolean.new.cast(@inherit_acquisition) || false
  end
end
