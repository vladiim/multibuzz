class Account < ApplicationRecord
  include Account::Validations
  include Account::Relationships
  include Account::StatusManagement

  enum :status, { active: 0, suspended: 1, cancelled: 2 }
end
