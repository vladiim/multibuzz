class User < ApplicationRecord
  include User::Validations
  include User::Relationships
  include User::Authentication
  include User::AccountAccess

  has_prefix_id :user

  # Legacy - remove after production migration verified
  enum :role, { member: 0, admin: 1 }
end
