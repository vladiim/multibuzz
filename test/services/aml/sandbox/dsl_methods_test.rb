# frozen_string_literal: true

require "test_helper"

module AML
  module Sandbox
    class DSLMethodsTest < ActiveSupport::TestCase
      # within_window tests
      test "within_window sets the lookback period" do
        context = build_context
        context.within_window(30.days) do
          apply 1.0, to: touchpoints[0]
        end

        assert_equal 30.days, context.lookback_window
      end

      test "within_window is required" do
        context = build_context

        assert_raises(::AML::ValidationError) do
          context.apply 1.0, to: context.touchpoints[0]
        end
      end

      # apply tests - fixed credit
      test "apply assigns fixed credit to single touchpoint" do
        credits = execute_aml do
          within_window 30.days do
            apply 1.0, to: touchpoints[0]
          end
        end

        assert_equal 1.0, credits[0]
        assert_equal 0.0, credits[1]
        assert_equal 0.0, credits[2]
        assert_equal 0.0, credits[3]
      end

      test "apply assigns credit to last touchpoint with negative index" do
        credits = execute_aml do
          within_window 30.days do
            apply 1.0, to: touchpoints[-1]
          end
        end

        assert_equal 0.0, credits[0]
        assert_equal 0.0, credits[1]
        assert_equal 0.0, credits[2]
        assert_equal 1.0, credits[3]
      end

      test "apply supports multiple assignments" do
        credits = execute_aml do
          within_window 30.days do
            apply 0.4, to: touchpoints[0]
            apply 0.4, to: touchpoints[-1]
            apply 0.2, to: touchpoints[1..-2], distribute: :equal
          end
        end

        assert_in_delta 0.4, credits[0], 0.0001
        assert_in_delta 0.1, credits[1], 0.0001
        assert_in_delta 0.1, credits[2], 0.0001
        assert_in_delta 0.4, credits[3], 0.0001
      end

      # apply with distribute: :equal
      test "apply distributes equally among multiple touchpoints" do
        credits = execute_aml do
          within_window 30.days do
            apply 1.0, to: touchpoints, distribute: :equal
          end
        end

        credits.each do |credit|
          assert_in_delta 0.25, credit, 0.0001
        end
      end

      # apply with calculated credit
      test "apply supports calculated credit" do
        credits = execute_aml do
          within_window 30.days do
            apply 1.0 / touchpoints.length, to: touchpoints
          end
        end

        credits.each do |credit|
          assert_in_delta 0.25, credit, 0.0001
        end
      end

      # time_decay tests
      test "time_decay applies exponential decay" do
        credits = execute_aml do
          within_window 30.days do
            time_decay half_life: 7.days
          end
        end

        # Last touchpoint should have highest credit
        assert credits[-1] > credits[0]
        # Credits should sum to 1.0
        assert_in_delta 1.0, credits.sum, 0.0001
      end

      # normalize! tests
      test "normalize! adjusts credits to sum to 1.0" do
        credits = execute_aml do
          within_window 30.days do
            apply 2.0, to: touchpoints[0]
            apply 2.0, to: touchpoints[-1]
            normalize!
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
        assert_in_delta 0.5, credits[0], 0.0001
        assert_in_delta 0.5, credits[-1], 0.0001
      end

      # Edge cases
      test "handles single touchpoint journey" do
        context = build_context(touchpoint_count: 1)
        credits = context.execute do
          within_window 30.days do
            apply 0.4, to: touchpoints[0]
            apply 0.4, to: touchpoints[-1]
            apply 0.2, to: touchpoints[1..-2], distribute: :equal
          end
        end

        # Single touchpoint gets all credit
        assert_in_delta 1.0, credits[0], 0.0001
      end

      test "handles two touchpoint journey" do
        context = build_context(touchpoint_count: 2)
        credits = context.execute do
          within_window 30.days do
            apply 0.4, to: touchpoints[0]
            apply 0.4, to: touchpoints[-1]
            apply 0.2, to: touchpoints[1..-2], distribute: :equal
          end
        end

        # No middle touchpoints, so 0.4 + 0.4 = 0.8, normalize to 1.0
        assert_in_delta 0.5, credits[0], 0.0001
        assert_in_delta 0.5, credits[1], 0.0001
      end

      test "handles empty touchpoint range gracefully" do
        credits = execute_aml do
          within_window 30.days do
            paid = touchpoints.select { |tp| tp.channel == "nonexistent" }
            if paid.any?
              apply 1.0, to: paid, distribute: :equal
            else
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
      end

      # Credit validation
      test "validates credits sum to 1.0 without normalize!" do
        assert_raises(::AML::CreditSumError) do
          execute_aml do
            within_window 30.days do
              apply 0.5, to: touchpoints[0]
              # Missing credits for the rest
            end
          end
        end
      end

      private

      def execute_aml(&block)
        context = build_context
        context.execute(&block)
      end

      def build_context(touchpoint_count: 4)
        touchpoints = (0...touchpoint_count).map do |i|
          {
            session_id: i + 1,
            channel: "channel_#{i}",
            occurred_at: (touchpoint_count - i).days.ago
          }
        end

        Context.new(
          touchpoints: touchpoints,
          conversion_time: Time.current,
          conversion_value: 100.0
        )
      end
    end
  end
end
