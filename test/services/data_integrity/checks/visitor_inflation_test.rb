require "test_helper"

module DataIntegrity
  module Checks
    class VisitorInflationTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when visitors per fingerprint below warning" do
        create_visitor_with_fingerprint("fp_aaa")
        create_visitor_with_fingerprint("fp_bbb")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.0, result[:value]
      end

      test "returns warning when visitors per fingerprint between thresholds" do
        create_visitor_with_fingerprint("fp_aaa", count: 2)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 2.0, result[:value]
      end

      test "returns critical when visitors per fingerprint above critical" do
        create_visitor_with_fingerprint("fp_aaa", count: 4)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 4.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "excludes sessions with nil fingerprint" do
        create_visitor_with_fingerprint("fp_aaa")
        create_visitor_with_fingerprint(nil, count: 3)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.0, result[:value]
      end

      test "excludes sessions older than 7 days" do
        create_visitor_with_fingerprint("fp_aaa", count: 3, started_at: 8.days.ago)
        create_visitor_with_fingerprint("fp_bbb")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.0, result[:value]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "visitor_inflation", result[:check_name]
        assert_in_delta 1.5, result[:warning_threshold]
        assert_in_delta 3.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def check = DataIntegrity::Checks::VisitorInflation.new(account)

      def create_visitor_with_fingerprint(fingerprint, count: 1, started_at: 1.day.ago)
        count.times do
          v = account.visitors.create!(
            visitor_id: "vis_#{SecureRandom.hex(8)}",
            first_seen_at: started_at,
            last_seen_at: started_at
          )
          account.sessions.create!(
            visitor: v,
            session_id: "sess_#{SecureRandom.hex(8)}",
            started_at: started_at,
            device_fingerprint: fingerprint
          )
        end
      end
    end
  end
end
