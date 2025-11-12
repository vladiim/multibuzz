class Visitor < ApplicationRecord
  include Visitor::Validations
  include Visitor::Relationships
  include Visitor::Scopes
  include Visitor::Tracking
  include Visitor::Callbacks

  has_prefix_id :vis
end
