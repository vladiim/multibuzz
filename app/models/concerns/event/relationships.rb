module Event::Relationships
  extend ActiveSupport::Concern

  included do
    belongs_to :account
    belongs_to :visitor
    belongs_to :session
  end
end
