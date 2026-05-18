# frozen_string_literal: true

module ReattributionBatch::Validations
  extend ActiveSupport::Concern

  included do
    validates :trigger, presence: true
    validates :total, :processed, :failed,
      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  end
end
