# frozen_string_literal: true

module AML
  module SecurityTestHelper
    def assert_forbidden(code, message = nil)
      error = assert_raises(::AML::SecurityError, message) do
        ::AML::Security::ASTAnalyzer.new(code).analyze!
      end

      assert_match(/forbidden|not allowed|blocked/i, error.message, message)
    end

    def assert_allowed(code, _message = nil)
      assert_nothing_raised do
        ::AML::Security::ASTAnalyzer.new(code).analyze!
      end
    end
  end
end
