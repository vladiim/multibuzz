class Event < ApplicationRecord
  include Event::Validations
  include Event::Relationships
  include Event::Scopes
  include Event::PropertyAccess

  has_prefix_id :evt
end
