class AttributionCredit < ApplicationRecord
  include AttributionCredit::Relationships
  include AttributionCredit::Validations

  has_prefix_id :cred
end
