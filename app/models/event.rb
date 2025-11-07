class Event < ApplicationRecord
  include Event::Validations
  include Event::Relationships
  include Event::Scopes
  include Event::PropertyAccess
end
