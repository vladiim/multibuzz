class Account < ApplicationRecord
  include Account::Validations
  include Account::Relationships
  include Account::StatusManagement
  include Account::Billing
  include Account::Callbacks
  include Account::Onboarding

  has_prefix_id :acct

  enum :status, { active: 0, suspended: 1, cancelled: 2 }
end
