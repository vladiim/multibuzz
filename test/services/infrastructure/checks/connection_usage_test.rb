# frozen_string_literal: true

require "test_helper"

module Infrastructure
  module Checks
    class ConnectionUsageTest < ActiveSupport::TestCase
      test "returns ok for normal connection count" do
        result = check.call

        assert_equal :ok, result[:status]
      end

      test "returns connection_usage as check name" do
        assert_equal "connection_usage", check.call[:name]
      end

      test "value is a percentage" do
        result = check.call

        assert_kind_of Numeric, result[:value]
        assert_operator result[:value], :>=, 0
        assert_operator result[:value], :<=, 100
      end

      private

      def check = @check ||= Infrastructure::Checks::ConnectionUsage.new
    end
  end
end
