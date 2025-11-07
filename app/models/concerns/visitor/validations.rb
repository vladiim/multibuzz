module Visitor::Validations
  extend ActiveSupport::Concern

  included do
    validates :visitor_id,
      presence: true,
      uniqueness: { scope: :account_id },
      format: {
        with: /\A[a-z0-9_-]{3,}\z/i,
        message: "must be at least 3 characters and contain only letters, numbers, underscores, and hyphens"
      }
  end
end
