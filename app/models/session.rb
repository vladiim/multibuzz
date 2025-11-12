class Session < ApplicationRecord
  include Session::Validations
  include Session::Relationships
  include Session::Scopes
  include Session::Tracking
  include Session::Callbacks

  has_prefix_id :sess
end
