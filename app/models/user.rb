class User < ApplicationRecord
  include User::Validations
  include User::Relationships
  include User::Authentication
  include User::AccountAccess
  include User::Roles

  has_prefix_id :user
end
