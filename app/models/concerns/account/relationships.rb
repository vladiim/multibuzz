module Account::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :account_memberships, dependent: :destroy
    has_many :members, through: :account_memberships, source: :user

    # Legacy - will be removed after migration complete
    has_many :users, dependent: :destroy
    has_many :api_keys, dependent: :destroy
    has_many :visitors, dependent: :destroy
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy
    has_many :conversions, dependent: :destroy
    has_many :attribution_models, dependent: :destroy
    has_many :attribution_credits, dependent: :destroy
  end
end
