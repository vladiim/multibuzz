# frozen_string_literal: true

require "test_helper"

module Infrastructure
  module Checks
    class QueueDepthTest < ActiveSupport::TestCase
      test "returns queue_depth as check name" do
        assert_equal "queue_depth", check.call[:name]
      end

      test "returns error status when queue database unavailable" do
        # SolidQueue connects to the queue database which is not available in test
        assert_equal :error, check.call[:status]
      end

      private

      def check = @check ||= Infrastructure::Checks::QueueDepth.new
    end
  end
end
