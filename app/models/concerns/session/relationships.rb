module Session::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :visitor
    has_many :events, dependent: :destroy
  end
end
