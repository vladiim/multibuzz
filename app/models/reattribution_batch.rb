# frozen_string_literal: true

class ReattributionBatch < ApplicationRecord
  include ReattributionBatch::Enums
  include ReattributionBatch::Relationships
  include ReattributionBatch::Validations
  include ReattributionBatch::Scopes

  has_prefix_id :rbatch
end
