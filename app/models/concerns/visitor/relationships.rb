module Visitor::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :identity, optional: true, inverse_of: :visitors, class_name: "Identity"
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy

    # Override to bypass Identity's default scope
    def identity
      return nil unless identity_id

      Identity.unscope(where: :is_test).find_by(id: identity_id)
    end
  end
end
