module Account::Validations
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
    validates :slug,
      presence: true,
      uniqueness: true,
      format: {
        with: /\A[a-z0-9-]+\z/,
        message: "must be lowercase letters, numbers, and hyphens only"
      }
  end
end
