class Session < ApplicationRecord
  include Session::Validations
  include Session::Relationships
  include Session::Scopes
  include Session::Tracking
  include Session::Callbacks
end
