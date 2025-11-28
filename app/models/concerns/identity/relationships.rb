module Identity::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :visitors, dependent: :nullify
  end
end
