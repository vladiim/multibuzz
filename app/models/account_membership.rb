class AccountMembership < ApplicationRecord
  include AccountMembership::Validations
  include AccountMembership::Relationships
  include AccountMembership::Scopes

  has_prefix_id :mem

  enum :role, { viewer: 0, member: 1, admin: 2, owner: 3 }
  enum :status, { pending: 0, accepted: 1, declined: 2, revoked: 3 }
end
