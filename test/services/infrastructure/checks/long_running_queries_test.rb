# frozen_string_literal: true

require "test_helper"

module Infrastructure
  module Checks
    class LongRunningQueriesTest < ActiveSupport::TestCase
      test "returns ok with no long-running queries" do
        result = check.call

        assert_equal :ok, result[:status]
        assert_equal 0, result[:value]
      end

      test "returns long_running_queries as check name" do
        assert_equal "long_running_queries", check.call[:name]
      end

      private

      def check = @check ||= Infrastructure::Checks::LongRunningQueries.new
    end
  end
end
