class AttributionCredit < ApplicationRecord
  include AttributionCredit::Relationships
  include AttributionCredit::Validations
end
