# frozen_string_literal: true

require "test_helper"

module AML
  class ErrorsTest < ActiveSupport::TestCase
    test "base error includes message" do
      error = AML::Error.new("Something went wrong")

      assert_equal "Something went wrong", error.message
    end

    test "base error includes line and column when provided" do
      error = AML::Error.new("Invalid syntax", line: 3, column: 10)

      assert_equal 3, error.line
      assert_equal 10, error.column
      assert_includes error.message, "line 3"
      assert_includes error.message, "column 10"
    end

    test "base error includes suggestion when provided" do
      error = AML::Error.new("Credits don't sum to 1.0", suggestion: "Add normalize!")

      assert_includes error.message, "Add normalize!"
    end

    test "SecurityError inherits from Error" do
      error = AML::SecurityError.new("Forbidden method: eval")

      assert_kind_of AML::Error, error
      assert_includes error.message, "eval"
    end

    test "SyntaxError inherits from Error" do
      error = AML::SyntaxError.new("Unexpected token", line: 5)

      assert_kind_of AML::Error, error
      assert_includes error.message, "line 5"
    end

    test "ValidationError inherits from Error" do
      error = AML::ValidationError.new("Missing within_window")

      assert_kind_of AML::Error, error
    end

    test "ExecutionError inherits from Error" do
      error = AML::ExecutionError.new("Execution failed")

      assert_kind_of AML::Error, error
    end

    test "TimeoutError inherits from ExecutionError" do
      error = AML::TimeoutError.new("Execution exceeded 5 seconds")

      assert_kind_of AML::ExecutionError, error
      assert_kind_of AML::Error, error
    end

    test "IterationLimitError inherits from ExecutionError" do
      error = AML::IterationLimitError.new("Exceeded 10,000 iterations")

      assert_kind_of AML::ExecutionError, error
    end

    test "CreditSumError inherits from ValidationError" do
      error = AML::CreditSumError.new("Credits sum to 1.2", suggestion: "Reduce assignments by 0.2")

      assert_kind_of AML::ValidationError, error
      assert_includes error.message, "1.2"
      assert_includes error.message, "0.2"
    end
  end
end
