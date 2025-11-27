class User < ApplicationRecord
  include User::Validations
  include User::Relationships
  include User::Authentication
  include User::AccountAccess

  has_prefix_id :user

  # Legacy - will be removed after migration complete
  enum :role, { member: 0, admin: 1 }
end
