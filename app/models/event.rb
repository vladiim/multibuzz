class Event < ApplicationRecord
  include Event::Validations
  include Event::Relationships
  include Event::Scopes
  include Event::PropertyAccess

  has_prefix_id :evt

  # TimescaleDB hypertable has composite primary key (id, occurred_at)
  # But we want ActiveRecord to use just :id for associations/fixtures
  self.primary_key = :id
end
