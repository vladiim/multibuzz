require "test_helper"

module DataIntegrity
  module Checks
    class FingerprintInstabilityTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when all visitors have stable fingerprints" do
        v = create_visitor
        create_session(visitor: v, fingerprint: "fp_aaa", started_at: 1.day.ago)
        create_session(visitor: v, fingerprint: "fp_aaa", started_at: 1.day.ago + 1.hour)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns warning when instability rate between thresholds" do
        # 1 unstable out of 5 = 20%
        unstable = create_visitor
        create_session(visitor: unstable, fingerprint: "fp_aaa", started_at: 1.day.ago)
        create_session(visitor: unstable, fingerprint: "fp_bbb", started_at: 1.day.ago + 1.hour)

        4.times do
          v = create_visitor
          create_session(visitor: v, fingerprint: "fp_#{SecureRandom.hex(4)}", started_at: 1.day.ago)
        end

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 20.0, result[:value]
      end

      test "returns critical when instability rate above critical" do
        # 3 unstable out of 5 = 60%
        3.times do
          v = create_visitor
          create_session(visitor: v, fingerprint: "fp_aaa_#{SecureRandom.hex(2)}", started_at: 1.day.ago)
          create_session(visitor: v, fingerprint: "fp_bbb_#{SecureRandom.hex(2)}", started_at: 1.day.ago + 1.hour)
        end

        2.times do
          v = create_visitor
          create_session(visitor: v, fingerprint: "fp_stable_#{SecureRandom.hex(4)}", started_at: 1.day.ago)
        end

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 60.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "only detects instability within same day" do
        v = create_visitor
        create_session(visitor: v, fingerprint: "fp_aaa", started_at: 2.days.ago)
        create_session(visitor: v, fingerprint: "fp_bbb", started_at: 1.day.ago)

        result = check.call

        assert_equal :healthy, result[:status]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "fingerprint_instability", result[:check_name]
        assert_in_delta 10.0, result[:warning_threshold]
        assert_in_delta 25.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def check = DataIntegrity::Checks::FingerprintInstability.new(account)

      def create_visitor
        account.visitors.create!(
          visitor_id: "vis_#{SecureRandom.hex(8)}",
          first_seen_at: 2.days.ago,
          last_seen_at: 1.day.ago
        )
      end

      def create_session(visitor:, fingerprint:, started_at:)
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
