module User::Relationships
  extend ActiveSupport::Concern

  included do
    # Legacy - will be removed after migration complete
    belongs_to :account, optional: true

    # New multi-account associations
    has_many :account_memberships, dependent: :destroy
    has_many :accounts, through: :account_memberships
  end
end
