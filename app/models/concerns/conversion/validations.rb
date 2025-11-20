# frozen_string_literal: true

module Conversion::Validations
  extend ActiveSupport::Concern

  included do
    validates :conversion_type, presence: true
    validates :converted_at, presence: true
    validates :revenue,
      numericality: { greater_than: 0 },
      allow_nil: true
  end
end
