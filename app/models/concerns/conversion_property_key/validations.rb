# frozen_string_literal: true

module ConversionPropertyKey::Validations
  extend ActiveSupport::Concern

  included do
    validates :property_key, presence: true
    validates :property_key, uniqueness: { scope: :account_id }
  end
end
