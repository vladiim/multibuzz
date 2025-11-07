module Visitor::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    has_many :sessions, dependent: :destroy
    has_many :events, dependent: :destroy
  end
end
