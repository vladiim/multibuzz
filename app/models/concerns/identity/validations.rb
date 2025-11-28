module Identity::Validations
  extend ActiveSupport::Concern

  included do
    validates :external_id, presence: true
    validates :external_id, uniqueness: { scope: :account_id }
    validates :first_identified_at, presence: true
    validates :last_identified_at, presence: true
  end
end
