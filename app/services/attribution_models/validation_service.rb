# frozen_string_literal: true

module AttributionModels
  class ValidationService
    def initialize(dsl_code)
      @dsl_code = dsl_code.to_s
    end

    def call
      analyzer.valid? ? success_result : error_result
    end

    private

    attr_reader :dsl_code

    def analyzer
      @analyzer ||= AML::Security::ASTAnalyzer.new(dsl_code)
    end

    def success_result
      { valid: true, errors: [] }
    end

    def error_result
      { valid: false, errors: [ error_hash ] }
    end

    def error_hash
      analyzer.analyze!
    rescue AML::SecurityError, AML::SyntaxError => e
      { message: e.message, line: e.try(:line), column: e.try(:column), suggestion: e.try(:suggestion) }
    end
  end
end
