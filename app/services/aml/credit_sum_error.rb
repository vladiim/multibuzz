# frozen_string_literal: true

module AML
  # Raised when credits don't sum to 1.0
  class CreditSumError < ValidationError; end
end
