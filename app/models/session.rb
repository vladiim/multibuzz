class Session < ApplicationRecord
  include Session::Validations
  include Session::Relationships
  include Session::Scopes
  include Session::Tracking
  include Session::Callbacks

  has_prefix_id :sess

  # TimescaleDB hypertable has composite primary key (id, started_at)
  # But we want ActiveRecord to use just :id for associations/fixtures
  self.primary_key = :id
end
