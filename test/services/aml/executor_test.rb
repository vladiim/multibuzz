# frozen_string_literal: true

require "test_helper"

module AML
  class ExecutorTest < ActiveSupport::TestCase
    # Happy path tests
    test "executes valid AML code and returns credits" do
      credits = build_executor(linear_model_code).call

      assert_equal 4, credits.length
      assert_in_delta 0.25, credits[0], 0.0001
      assert_in_delta 0.25, credits[1], 0.0001
      assert_in_delta 0.25, credits[2], 0.0001
      assert_in_delta 0.25, credits[3], 0.0001
    end

    test "executes first touch model" do
      credits = build_executor(first_touch_code).call

      assert_equal 1.0, credits[0]
      assert_equal 0.0, credits[1]
    end

    test "executes last touch model" do
      credits = build_executor(last_touch_code).call

      assert_equal 0.0, credits[0]
      assert_equal 1.0, credits[-1]
    end

    test "executes u-shaped model" do
      credits = build_executor(u_shaped_code).call

      assert_in_delta 0.4, credits[0], 0.0001
      assert_in_delta 0.1, credits[1], 0.0001
      assert_in_delta 0.1, credits[2], 0.0001
      assert_in_delta 0.4, credits[3], 0.0001
    end

    test "executes time decay model" do
      credits = build_executor(time_decay_code).call

      # More recent touchpoints should have higher credit
      assert credits[-1] > credits[0]
      assert_in_delta 1.0, credits.sum, 0.0001
    end

    # Security rejection tests
    test "rejects code with system calls" do
      error = assert_raises(::AML::SecurityError) do
        build_executor('system("rm -rf /")').call
      end

      assert_includes error.message, "system"
    end

    test "rejects code with backticks" do
      error = assert_raises(::AML::SecurityError) do
        build_executor('`ls`').call
      end

      assert_includes error.message, "Backtick"
    end

    test "rejects code with require" do
      error = assert_raises(::AML::SecurityError) do
        build_executor('require "net/http"').call
      end

      assert_includes error.message, "require"
    end

    test "rejects code with eval" do
      error = assert_raises(::AML::SecurityError) do
        build_executor('eval("1+1")').call
      end

      assert_includes error.message, "eval"
    end

    test "rejects code with constant access" do
      error = assert_raises(::AML::SecurityError) do
        build_executor("File.read('/etc/passwd')").call
      end

      assert_includes error.message, "File"
    end

    # Syntax error tests
    test "raises syntax error for invalid Ruby" do
      error = assert_raises(::AML::SyntaxError) do
        build_executor("def foo(").call
      end

      assert_includes error.message, "unexpected"
    end

    # Validation error tests
    test "raises validation error when credits don't sum to 1.0" do
      error = assert_raises(::AML::CreditSumError) do
        build_executor(invalid_credit_sum_code).call
      end

      assert_includes error.message, "sum to"
    end

    test "raises validation error when within_window is missing" do
      error = assert_raises(::AML::ValidationError) do
        build_executor(missing_within_window_code).call
      end

      assert_includes error.message, "within_window"
    end

    private

    def build_executor(dsl_code)
      AML::Executor.new(
        dsl_code: dsl_code,
        touchpoints: touchpoints,
        conversion_time: Time.current,
        conversion_value: 100.0
      )
    end

    def touchpoints
      @touchpoints ||= [
        { session_id: 1, channel: "organic", occurred_at: 10.days.ago },
        { session_id: 2, channel: "email", occurred_at: 5.days.ago },
        { session_id: 3, channel: "paid_social", occurred_at: 2.days.ago },
        { session_id: 4, channel: "paid_search", occurred_at: 1.day.ago }
      ]
    end

    def linear_model_code
      <<~AML
        within_window 30.days do
          apply 1.0, to: touchpoints, distribute: :equal
        end
      AML
    end

    def first_touch_code
      <<~AML
        within_window 30.days do
          apply 1.0, to: touchpoints.first
        end
      AML
    end

    def last_touch_code
      <<~AML
        within_window 30.days do
          apply 1.0, to: touchpoints.last
        end
      AML
    end

    def u_shaped_code
      <<~AML
        within_window 30.days do
          apply 0.4, to: touchpoints.first
          apply 0.4, to: touchpoints.last
          apply 0.2, to: touchpoints[1..-2], distribute: :equal
        end
      AML
    end

    def time_decay_code
      <<~AML
        within_window 30.days do
          time_decay half_life: 7.days
        end
      AML
    end

    def invalid_credit_sum_code
      <<~AML
        within_window 30.days do
          apply 0.5, to: touchpoints.first
        end
      AML
    end

    def missing_within_window_code
      <<~AML
        apply 1.0, to: touchpoints.first
      AML
    end
  end
end
