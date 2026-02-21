# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  module Checks
    class MissingFingerprintRateTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when missing rate below warning" do
        create_session(fingerprint: "fp_aaa")
        create_session(fingerprint: "fp_bbb")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns warning when missing rate between thresholds" do
        9.times { create_session(fingerprint: "fp_#{SecureRandom.hex(4)}") }
        1.times { create_session(fingerprint: nil) }

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 10.0, result[:value]
      end

      test "returns critical when missing rate above critical" do
        3.times { create_session(fingerprint: "fp_#{SecureRandom.hex(4)}") }
        7.times { create_session(fingerprint: nil) }

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 70.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "excludes sessions older than 24 hours" do
        create_session(fingerprint: nil, started_at: 25.hours.ago)
        create_session(fingerprint: "fp_aaa")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_equal 1, result[:details][:total_sessions]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "missing_fingerprint_rate", result[:check_name]
        assert_in_delta 5.0, result[:warning_threshold]
        assert_in_delta 20.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)
      def check = DataIntegrity::Checks::MissingFingerprintRate.new(account)

      def create_session(fingerprint:, started_at: 1.hour.ago)
        account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: started_at,
          device_fingerprint: fingerprint
        )
      end
    end
  end
end
