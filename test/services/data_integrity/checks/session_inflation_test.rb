require "test_helper"

module DataIntegrity
  module Checks
    class SessionInflationTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when sessions per fingerprint below warning" do
        create_sessions_with_fingerprint("fp_aaa", count: 1)
        create_sessions_with_fingerprint("fp_bbb", count: 2)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.5, result[:value]
      end

      test "returns warning when sessions per fingerprint between thresholds" do
        create_sessions_with_fingerprint("fp_aaa", count: 3)
        create_sessions_with_fingerprint("fp_bbb", count: 2)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 2.5, result[:value]
      end

      test "returns critical when sessions per fingerprint above critical" do
        create_sessions_with_fingerprint("fp_aaa", count: 6)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 6.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "excludes sessions with nil fingerprint" do
        create_sessions_with_fingerprint("fp_aaa", count: 1)
        create_sessions_with_fingerprint(nil, count: 5)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.0, result[:value]
      end

      test "excludes sessions older than 7 days" do
        create_sessions_with_fingerprint("fp_aaa", count: 5, started_at: 8.days.ago)
        create_sessions_with_fingerprint("fp_bbb", count: 1)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 1.0, result[:value]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "session_inflation", result[:check_name]
        assert_in_delta 2.0, result[:warning_threshold]
        assert_in_delta 5.0, result[:critical_threshold]
      end

      test "excludes suspect sessions from inflation calculation" do
        create_sessions_with_fingerprint("fp_aaa", count: 1)
        create_sessions_with_fingerprint("fp_bbb", count: 1, suspect: true)
        create_sessions_with_fingerprint("fp_bbb", count: 1, suspect: true)
        create_sessions_with_fingerprint("fp_bbb", count: 1, suspect: true)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_equal 1, result[:details][:total_sessions]
        assert_equal 1, result[:details][:unique_fingerprints]
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)
      def check = DataIntegrity::Checks::SessionInflation.new(account)

      def create_sessions_with_fingerprint(fingerprint, count:, started_at: 1.day.ago, suspect: false)
        count.times do
          account.sessions.create!(
            visitor: visitor,
            session_id: "sess_#{SecureRandom.hex(8)}",
            started_at: started_at,
            device_fingerprint: fingerprint,
            suspect: suspect
          )
        end
      end
    end
  end
end
