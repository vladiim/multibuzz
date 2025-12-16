# frozen_string_literal: true

require "test_helper"

module AML
  module Sandbox
    class NestedWindowTest < ActiveSupport::TestCase
      # Basic nested window tests
      test "nested within_window filters touchpoints to time range" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 1.0 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        # Only touchpoints within 30 days should get credit
        assert_equal 3, credits.count { |c| c > 0 }
      end

      test "nested within_window with range filters touchpoints" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days..60.days, weight: 1.0 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        # Only touchpoints between 30-60 days should get credit
        assert_equal 2, credits.count { |c| c > 0 }
      end

      # Weight distribution tests
      test "segment weights scale credits correctly" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 0.6 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
            within_window 30.days..60.days, weight: 0.4 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        recent_credits = credits[0..2].sum  # 0, 10, 20 days old
        older_credits = credits[3..4].sum   # 40, 50 days old

        assert_in_delta 0.6, recent_credits, 0.0001
        assert_in_delta 0.4, older_credits, 0.0001
        assert_in_delta 1.0, credits.sum, 0.0001
      end

      test "segment weights must sum to 1.0" do
        context = build_context_with_spread_touchpoints

        assert_raises(::AML::ValidationError) do
          context.execute do
            within_window 90.days do
              within_window 30.days, weight: 0.5 do
                apply 1.0, to: touchpoints, distribute: :equal
              end
              within_window 30.days..60.days, weight: 0.3 do
                apply 1.0, to: touchpoints, distribute: :equal
              end
              # Missing 0.2 weight
            end
          end
        end
      end

      # Empty segment handling
      test "empty segments redistribute weight to non-empty segments" do
        context = build_context_with_recent_touchpoints_only
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 0.6 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
            within_window 30.days..60.days, weight: 0.4 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        # All touchpoints are recent, so all credit goes to first segment
        # Weight is redistributed: 0.6 / 0.6 = 1.0
        assert_in_delta 1.0, credits.sum, 0.0001
      end

      # Time decay within segments
      test "time_decay works within nested window segment" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 0.6 do
              time_decay half_life: 7.days
            end
            within_window 30.days..60.days, weight: 0.4 do
              time_decay half_life: 14.days
            end
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
        # Recent segment should have 60% of total credit
        assert_in_delta 0.6, credits[0..2].sum, 0.0001
      end

      # Validation tests
      test "overlapping segments raise validation error" do
        context = build_context_with_spread_touchpoints

        assert_raises(::AML::ValidationError) do
          context.execute do
            within_window 90.days do
              within_window 30.days, weight: 0.5 do
                apply 1.0, to: touchpoints, distribute: :equal
              end
              within_window 20.days..50.days, weight: 0.5 do  # Overlaps with 0-30
                apply 1.0, to: touchpoints, distribute: :equal
              end
            end
          end
        end
      end

      test "segment range outside outer window raises error" do
        context = build_context_with_spread_touchpoints

        assert_raises(::AML::ValidationError) do
          context.execute do
            within_window 30.days do
              within_window 30.days..60.days, weight: 1.0 do  # Outside 30 day window
                apply 1.0, to: touchpoints, distribute: :equal
              end
            end
          end
        end
      end

      test "nesting deeper than 2 levels raises error" do
        context = build_context_with_spread_touchpoints

        assert_raises(::AML::ValidationError) do
          context.execute do
            within_window 90.days do
              within_window 60.days, weight: 1.0 do
                within_window 30.days, weight: 1.0 do  # Too deep
                  apply 1.0, to: touchpoints, distribute: :equal
                end
              end
            end
          end
        end
      end

      # Shorthand syntax tests
      test "single duration expands to 0..N range" do
        context = build_context_with_spread_touchpoints
        credits_shorthand = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 1.0 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        context2 = build_context_with_spread_touchpoints
        credits_explicit = context2.execute do
          within_window 90.days do
            within_window 0.days..30.days, weight: 1.0 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        assert_equal credits_shorthand, credits_explicit
      end

      # touchpoints.first/last within segment tests
      test "touchpoints.first within segment returns first of filtered collection" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 0.6 do
              apply 1.0, to: touchpoints.first
            end
            within_window 30.days..60.days, weight: 0.4 do
              apply 1.0, to: touchpoints.first
            end
          end
        end

        # First recent touchpoint and first older touchpoint get credit
        assert_equal 2, credits.count { |c| c > 0 }
        assert_in_delta 1.0, credits.sum, 0.0001
      end

      # Backward compatibility tests
      test "non-nested within_window still works without weight" do
        context = build_context
        credits = context.execute do
          within_window 30.days do
            apply 1.0, to: touchpoints, distribute: :equal
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
      end

      test "single segment with weight 1.0 works" do
        context = build_context
        credits = context.execute do
          within_window 60.days do
            within_window 30.days, weight: 1.0 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
      end

      # Three segment model test
      test "three segment model distributes credit correctly" do
        context = build_context_with_spread_touchpoints
        credits = context.execute do
          within_window 90.days do
            within_window 30.days, weight: 0.6 do
              time_decay half_life: 7.days
            end
            within_window 30.days..60.days, weight: 0.3 do
              time_decay half_life: 14.days
            end
            within_window 60.days..90.days, weight: 0.1 do
              apply 1.0, to: touchpoints, distribute: :equal
            end
          end
        end

        assert_in_delta 1.0, credits.sum, 0.0001
      end

      private

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

      def build_context_with_spread_touchpoints
        # 6 touchpoints spread across 0-80 days
        touchpoints = [
          { session_id: 1, channel: "organic", occurred_at: 0.days.ago },    # 0 days
          { session_id: 2, channel: "paid", occurred_at: 10.days.ago },      # 10 days
          { session_id: 3, channel: "email", occurred_at: 20.days.ago },     # 20 days
          { session_id: 4, channel: "social", occurred_at: 40.days.ago },    # 40 days
          { session_id: 5, channel: "referral", occurred_at: 50.days.ago },  # 50 days
          { session_id: 6, channel: "direct", occurred_at: 70.days.ago }     # 70 days
        ]

        Context.new(
          touchpoints: touchpoints,
          conversion_time: Time.current,
          conversion_value: 100.0
        )
      end

      def build_context_with_recent_touchpoints_only
        # All touchpoints within 30 days
        touchpoints = [
          { session_id: 1, channel: "organic", occurred_at: 0.days.ago },
          { session_id: 2, channel: "paid", occurred_at: 5.days.ago },
          { session_id: 3, channel: "email", occurred_at: 15.days.ago },
          { session_id: 4, channel: "social", occurred_at: 25.days.ago }
        ]

        Context.new(
          touchpoints: touchpoints,
          conversion_time: Time.current,
          conversion_value: 100.0
        )
      end
    end
  end
end
