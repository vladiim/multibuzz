module Conversion::Scopes
  extend ActiveSupport::Concern

  included do
    default_scope { production }

    scope :production, -> { where(is_test: false) }
    scope :test_data, -> { where(is_test: true) }
  end
end
