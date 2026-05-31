# frozen_string_literal: true

module Account::Relationships
  extend ActiveSupport::Concern

  included do
    has_many :account_memberships, dependent: :destroy
    has_many :members, through: :account_memberships, source: :user
    has_many :users, through: :account_memberships
    has_many :api_keys, dependent: :destroy
    has_one :guided_setup, dependent: :destroy

    # Order matters for dependent: :destroy (foreign key constraints)
    # Most dependent tables first, then their parents
    has_many :rerun_jobs, dependent: :destroy
    has_many :reattribution_batches, dependent: :destroy
    has_many :dimension_rules, dependent: :destroy       # depends on custom_dimensions
    has_many :custom_dimensions, dependent: :destroy
    has_many :conversion_property_keys, dependent: :destroy
    has_many :conversion_dispatches, dependent: :destroy
    has_many :conversion_destinations, dependent: :destroy
    has_many :attribution_credits, dependent: :destroy  # depends on conversions
    has_many :conversions, dependent: :destroy          # depends on visitors
    has_many :events, dependent: :destroy               # depends on visitors
    has_many :sessions, dependent: :destroy             # depends on visitors
    has_many :visitors, dependent: :destroy             # depends on identities
    has_many :identities, dependent: :destroy
    has_many :attribution_models, dependent: :destroy
    has_many :ad_spend_records, dependent: :destroy
    has_many :ad_platform_connections, dependent: :destroy
    has_many :data_integrity_checks, dependent: :destroy
    has_many :exports, dependent: :destroy
    has_many :score_assessments, dependent: :nullify
  end

  def owner_user
    account_memberships.owner.accepted.first&.user
  end

  # True when `user` should see the self-serve onboarding chrome
  # regardless of the account's actual setup_path. Today: a non-owner on
  # a teammate-path account -- the invited dev who needs to install, not
  # the owner who picked the path.
  def dev_on_teammate_path?(user)
    teammate? && user.present? && user != owner_user
  end
end
