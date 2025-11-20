# frozen_string_literal: true

module AttributionModel::Validations
  extend ActiveSupport::Concern

  included do
    validates :name, presence: true
    validates :name,
      uniqueness: { scope: :account_id }
    validates :lookback_days,
      presence: true,
      numericality: {
        only_integer: true,
        greater_than: 0,
        less_than_or_equal_to: 365
      }
  end
end
