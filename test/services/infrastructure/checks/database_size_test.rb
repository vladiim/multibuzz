# frozen_string_literal: true

require "test_helper"

module Infrastructure
  module Checks
    class DatabaseSizeTest < ActiveSupport::TestCase
      test "returns ok for small database" do
        result = check.call

        assert_equal :ok, result[:status]
        assert_predicate result[:value], :positive?
      end

      test "returns database_size as check name" do
        assert_equal "database_size", check.call[:name]
      end

      test "display value is human readable" do
        result = check.call

        assert_match(/\d+(\.\d+)?\s+(Bytes|KB|MB|GB|TB)/, result[:display])
      end

      private

      def check = @check ||= Infrastructure::Checks::DatabaseSize.new
    end
  end
end
