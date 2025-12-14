# frozen_string_literal: true

module AML
  # Base error class for all AML-related errors
  class Error < StandardError
    attr_reader :line, :column, :suggestion

    def initialize(message, line: nil, column: nil, suggestion: nil)
      @line = line
      @column = column
      @suggestion = suggestion
      super(build_message(message))
    end

    private

    def build_message(message)
      parts = [message]
      parts << "at line #{line}, column #{column}" if line && column
      parts << "at line #{line}" if line && !column
      parts << "Suggestion: #{suggestion}" if suggestion
      parts.join(" - ")
    end
  end
end
