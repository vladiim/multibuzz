class AttributionCredit < ApplicationRecord
  include AttributionCredit::Relationships
  include AttributionCredit::Validations
  include AttributionCredit::Scopes
  include AttributionCredit::Callbacks

  has_prefix_id :cred
end
