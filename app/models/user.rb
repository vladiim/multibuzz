class User < ApplicationRecord
  include User::Validations
  include User::Relationships
  include User::Authentication

  has_prefix_id :user

  enum :role, { member: 0, admin: 1 }
end
