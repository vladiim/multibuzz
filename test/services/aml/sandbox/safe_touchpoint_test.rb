# frozen_string_literal: true

require "test_helper"

module AML
  module Sandbox
    class SafeTouchpointTest < ActiveSupport::TestCase
      test "exposes session_id" do
        assert_equal 1, touchpoint.session_id
      end

      test "exposes channel" do
        assert_equal "paid_search", touchpoint.channel
      end

      test "exposes occurred_at" do
        assert_instance_of ActiveSupport::TimeWithZone, touchpoint.occurred_at
      end

      test "exposes event_type" do
        assert_equal "page_view", touchpoint.event_type
      end

      test "exposes properties as read-only hash" do
        assert_equal "google", touchpoint.properties["utm_source"]
      end

      test "properties support dig" do
        tp = SafeTouchpoint.new(
          session_id: 1,
          channel: "paid",
          occurred_at: Time.current,
          properties: { "nested" => { "value" => 123 } }
        )
        assert_equal 123, tp.properties.dig("nested", "value")
      end

      test "channel supports start_with?" do
        assert touchpoint.channel.start_with?("paid")
      end

      test "channel supports end_with?" do
        assert touchpoint.channel.end_with?("search")
      end

      test "channel supports include?" do
        assert touchpoint.channel.include?("search")
      end

      test "channel supports comparison" do
        assert_equal "paid_search", touchpoint.channel
      end

      test "occurred_at supports time comparison" do
        assert touchpoint.occurred_at < Time.current
        assert touchpoint.occurred_at > 10.days.ago
      end

      test "occurred_at supports between?" do
        assert touchpoint.occurred_at.between?(10.days.ago, Time.current)
      end

      test "blocks dangerous method calls" do
        assert_raises(::AML::SecurityError) do
          touchpoint.send(:system, "ls")
        end
      end

      test "blocks instance_variable_get" do
        assert_raises(::AML::SecurityError) do
          touchpoint.instance_variable_get(:@channel)
        end
      end

      private

      def touchpoint
        @touchpoint ||= SafeTouchpoint.new(
          session_id: 1,
          channel: "paid_search",
          occurred_at: 1.day.ago,
          event_type: "page_view",
          properties: { "utm_source" => "google" }
        )
      end
    end
  end
end
