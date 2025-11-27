module User::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :account_memberships, dependent: :destroy
    has_many :accounts, through: :account_memberships
  end
end
