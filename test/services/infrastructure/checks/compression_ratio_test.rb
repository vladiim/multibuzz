# frozen_string_literal: true

require "test_helper"

module Infrastructure
  module Checks
    class CompressionRatioTest < ActiveSupport::TestCase
      test "returns ok when no compressed data exists" do
        result = check.call

        # Test env has no hypertables, so query returns empty — defaults to 100%
        assert_equal :ok, result[:status]
      end

      test "returns compression_ratio as check name" do
        assert_equal "compression_ratio", check.call[:name]
      end

      test "display value shows percentage" do
        result = check.call

        assert_match(/%/, result[:display])
      end

      private

      def check = @check ||= Infrastructure::Checks::CompressionRatio.new
    end
  end
end
