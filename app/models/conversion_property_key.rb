# frozen_string_literal: true

class ConversionPropertyKey < ApplicationRecord
  include ConversionPropertyKey::Relationships
  include ConversionPropertyKey::Validations
  include ConversionPropertyKey::Scopes
end
