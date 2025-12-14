# frozen_string_literal: true

module AML
  # Raised when execution times out
  class TimeoutError < ExecutionError; end
end
