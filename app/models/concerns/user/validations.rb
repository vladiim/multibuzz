module User::Validations
  extend ActiveSupport::Concern

  included do
    validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
    validates :password, length: { minimum: 8 }, if: -> { password.present? }
  end
end
