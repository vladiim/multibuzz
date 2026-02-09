module Account::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :account_memberships, dependent: :destroy
    has_many :members, through: :account_memberships, source: :user
    has_many :users, through: :account_memberships
    has_many :api_keys, dependent: :destroy

    # Order matters for dependent: :destroy (foreign key constraints)
    # Most dependent tables first, then their parents
    has_many :rerun_jobs, dependent: :destroy
    has_many :conversion_property_keys, dependent: :destroy
    has_many :attribution_credits, dependent: :destroy  # depends on conversions
    has_many :conversions, dependent: :destroy          # depends on visitors
    has_many :events, dependent: :destroy               # depends on visitors
    has_many :sessions, dependent: :destroy             # depends on visitors
    has_many :visitors, dependent: :destroy             # depends on identities
    has_many :identities, dependent: :destroy
    has_many :attribution_models, dependent: :destroy
    has_many :data_integrity_checks, dependent: :destroy
  end
end
