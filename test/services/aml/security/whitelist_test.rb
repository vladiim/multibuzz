# frozen_string_literal: true

require "test_helper"
require_relative "../security_test_helper"

module AML
  module Security
    class WhitelistTest < ActiveSupport::TestCase
      include AML::SecurityTestHelper

      # Array methods
      test "allows array index access" do
        assert_allowed "touchpoints[0]"
      end

      test "allows array range access" do
        assert_allowed "touchpoints[1..-2]"
      end

      test "allows array length" do
        assert_allowed "touchpoints.length"
      end

      test "allows array size" do
        assert_allowed "touchpoints.size"
      end

      test "allows array count" do
        assert_allowed "touchpoints.count"
      end

      test "allows array first" do
        assert_allowed "touchpoints.first"
      end

      test "allows array last" do
        assert_allowed "touchpoints.last"
      end

      test "allows array select" do
        assert_allowed "touchpoints.select { |tp| tp.channel == 'paid' }"
      end

      test "allows array reject" do
        assert_allowed "touchpoints.reject { |tp| tp.channel == 'direct' }"
      end

      test "allows array find" do
        assert_allowed "touchpoints.find { |tp| tp.channel == 'email' }"
      end

      test "allows array map" do
        assert_allowed "touchpoints.map { |tp| tp.channel }"
      end

      test "allows array each" do
        assert_allowed "touchpoints.each { |tp| tp.channel }"
      end

      test "allows array each_with_index" do
        assert_allowed "touchpoints.each_with_index { |tp, i| i }"
      end

      test "allows array subtraction" do
        assert_allowed "touchpoints - excluded"
      end

      test "allows array any?" do
        assert_allowed "touchpoints.any?"
      end

      test "allows array empty?" do
        assert_allowed "touchpoints.empty?"
      end

      test "allows array sum" do
        assert_allowed "touchpoints.sum { |tp| 1 }"
      end

      # String methods
      test "allows string comparison" do
        assert_allowed 'channel == "paid_search"'
      end

      test "allows string start_with?" do
        assert_allowed 'channel.start_with?("paid_")'
      end

      test "allows string end_with?" do
        assert_allowed 'channel.end_with?("_search")'
      end

      test "allows string include?" do
        assert_allowed 'channel.include?("paid")'
      end

      test "allows string match?" do
        assert_allowed "channel.match?(/paid/)"
      end

      # Numeric operations
      test "allows arithmetic" do
        assert_allowed "1.0 / touchpoints.length"
      end

      test "allows comparison" do
        assert_allowed "credit > 0.5"
      end

      test "allows between?" do
        assert_allowed "credit.between?(0.0, 1.0)"
      end

      test "allows round" do
        assert_allowed "credit.round(4)"
      end

      # Time operations
      test "allows time comparison" do
        assert_allowed "tp.occurred_at > 7.days.ago"
      end

      test "allows time between?" do
        assert_allowed "tp.occurred_at.between?(30.days.ago, Time.current)"
      end

      test "allows days.ago" do
        assert_allowed "7.days.ago"
      end

      test "allows time arithmetic" do
        assert_allowed "(conversion_time - tp.occurred_at) / 1.day"
      end

      # Control flow
      test "allows if/else" do
        assert_allowed "if touchpoints.length > 3 then 0.4 else 0.5 end"
      end

      test "allows case/when" do
        assert_allowed "case touchpoints.length\nwhen 1 then 1.0\nwhen 2 then 0.5\nelse 0.25\nend"
      end

      test "allows ternary operator" do
        assert_allowed "touchpoints.length > 1 ? 0.5 : 1.0"
      end

      # Hash operations
      test "allows hash access" do
        assert_allowed 'tp.properties["utm_source"]'
      end

      test "allows hash dig" do
        assert_allowed 'tp.properties.dig("nested", "value")'
      end

      test "allows hash key?" do
        assert_allowed 'tp.properties.key?("utm_source")'
      end

      # Math operations
      test "allows Math.exp" do
        assert_allowed "Math.exp(-1)"
      end

      test "allows Math.log" do
        assert_allowed "Math.log(2)"
      end

      test "allows exponentiation" do
        assert_allowed "2 ** (-days / 7.0)"
      end
    end
  end
end
