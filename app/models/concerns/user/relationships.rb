module User::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
  end
end
