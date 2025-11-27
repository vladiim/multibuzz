class AttributionCredit < ApplicationRecord
  include AttributionCredit::Relationships
  include AttributionCredit::Validations
  include AttributionCredit::Scopes

  has_prefix_id :cred
end
