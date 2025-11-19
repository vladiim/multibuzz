# frozen_string_literal: true

module AttributionCredit::Validations
  extend ActiveSupport::Concern

  included do
    validates :channel, presence: true
    validates :credit,
      presence: true,
      numericality: {
        greater_than_or_equal_to: 0,
        less_than_or_equal_to: 1
      }
  end
end
