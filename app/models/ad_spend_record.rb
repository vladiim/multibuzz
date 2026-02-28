# frozen_string_literal: true

class AdSpendRecord < ApplicationRecord
  include AdSpendRecord::Validations
  include AdSpendRecord::Relationships
  include AdSpendRecord::Scopes

  has_prefix_id :aspend

  MICRO_UNIT = 1_000_000

  def spend
    spend_micros.to_d / MICRO_UNIT
  end

  def platform_conversion_value
    platform_conversion_value_micros.to_d / MICRO_UNIT
  end
end
