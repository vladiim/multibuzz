module ApiKey::Validations
  extend ActiveSupport::Concern

  included do
    validates :key_digest,
      presence: true,
      uniqueness: true
    validates :key_prefix, presence: true
  end
end
