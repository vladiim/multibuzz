module AccountMembership::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :user
    belongs_to :account
  end
end
