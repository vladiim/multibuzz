class AttributionModel < ApplicationRecord
  include AttributionModel::Enums
  include AttributionModel::Relationships
  include AttributionModel::Validations
  include AttributionModel::Scopes
  include AttributionModel::Callbacks

  has_prefix_id :attr
end
