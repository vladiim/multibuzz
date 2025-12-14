# frozen_string_literal: true

require "test_helper"

module AML
  module Sandbox
    class ContextTest < ActiveSupport::TestCase
      test "exposes touchpoints" do
        assert_equal 4, context.touchpoints.length
      end

      test "exposes conversion_time" do
        assert_instance_of ActiveSupport::TimeWithZone, context.conversion_time
      end

      test "exposes conversion_value" do
        assert_equal 100.0, context.conversion_value
      end

      test "touchpoints are read-only wrappers" do
        tp = context.touchpoints.first
        assert_equal "organic_search", tp.channel
        assert_respond_to tp, :occurred_at
        assert_respond_to tp, :session_id
      end

      test "touchpoints support array indexing" do
        assert_equal "organic_search", context.touchpoints[0].channel
        assert_equal "paid_search", context.touchpoints[-1].channel
      end

      test "touchpoints support range indexing" do
        middle = context.touchpoints[1..-2]
        assert_equal 2, middle.length
        assert_equal "email", middle.first.channel
      end

      test "touchpoints support select" do
        paid = context.touchpoints.select { |tp| tp.channel.start_with?("paid") }
        assert_equal 2, paid.length  # paid_social and paid_search
      end

      test "touchpoints support reject" do
        non_paid = context.touchpoints.reject { |tp| tp.channel.start_with?("paid") }
        assert_equal 2, non_paid.length  # organic_search and email
      end

      test "touchpoints support find" do
        email = context.touchpoints.find { |tp| tp.channel == "email" }
        assert_equal "email", email.channel
      end

      test "touchpoints support each_with_index" do
        indices = []
        context.touchpoints.each_with_index { |_, i| indices << i }
        assert_equal [0, 1, 2, 3], indices
      end

      test "touchpoints support subtraction" do
        first = [context.touchpoints.first]
        rest = context.touchpoints - first
        assert_equal 3, rest.length
      end

      test "touchpoints support sum" do
        total = context.touchpoints.sum { |_| 1 }
        assert_equal 4, total
      end

      test "blocks method_missing for undefined methods" do
        assert_raises(::AML::SecurityError) do
          context.undefined_method
        end
      end

      test "blocks access to dangerous methods" do
        assert_raises(::AML::SecurityError) do
          context.instance_eval { system("ls") }
        end
      end

      private

      def context
        @context ||= AML::Sandbox::Context.new(
          touchpoints: touchpoints,
          conversion_time: Time.current,
          conversion_value: 100.0
        )
      end

      def touchpoints
        @touchpoints ||= [
          { session_id: 1, channel: "organic_search", occurred_at: 10.days.ago },
          { session_id: 2, channel: "email", occurred_at: 5.days.ago },
          { session_id: 3, channel: "paid_social", occurred_at: 2.days.ago },
          { session_id: 4, channel: "paid_search", occurred_at: 1.day.ago }
        ]
      end
    end
  end
end
