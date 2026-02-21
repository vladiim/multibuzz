# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  module Checks
    class ExtremeSessionVisitorsTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when no visitors have 50+ sessions" do
        v = create_visitor
        10.times { create_session(visitor: v) }

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns warning when extreme visitors between thresholds" do
        # 1 extreme out of 50 = 2%
        extreme = create_visitor
        51.times { create_session(visitor: extreme) }

        49.times do
          v = create_visitor
          create_session(visitor: v)
        end

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 2.0, result[:value]
      end

      test "returns critical when extreme visitors above critical" do
        # 3 extreme out of 10 = 30%
        3.times do
          v = create_visitor
          51.times { create_session(visitor: v) }
        end

        7.times do
          v = create_visitor
          create_session(visitor: v)
        end

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 30.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "uses 30 day window" do
        # Extreme visitor but sessions are older than 30 days
        v = create_visitor
        51.times { create_session(visitor: v, started_at: 31.days.ago) }

        normal = create_visitor
        create_session(visitor: normal)

        result = check.call

        assert_equal :healthy, result[:status]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "extreme_session_visitors", result[:check_name]
        assert_in_delta 1.0, result[:warning_threshold]
        assert_in_delta 5.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def check = DataIntegrity::Checks::ExtremeSessionVisitors.new(account)

      def create_visitor
        account.visitors.create!(
          visitor_id: "vis_#{SecureRandom.hex(8)}",
          first_seen_at: 30.days.ago,
          last_seen_at: 1.day.ago
        )
      end

      def create_session(visitor:, started_at: 1.day.ago)
        account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: started_at
        )
      end
    end
  end
end
