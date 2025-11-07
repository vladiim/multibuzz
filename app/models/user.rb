class User < ApplicationRecord
  include User::Validations
  include User::Relationships
  include User::Authentication

  enum :role, { member: 0, admin: 1 }
end
