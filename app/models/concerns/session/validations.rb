module Session::Validations
  extend ActiveSupport::Concern

  included do
    validates :session_id,
      presence: true,
      uniqueness: { scope: :account_id }
  end
end
