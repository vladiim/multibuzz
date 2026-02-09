require "test_helper"

module DataIntegrity
  module Checks
    class AttributionMismatchTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
        account.conversions.destroy_all
      end

      test "returns healthy when channels match" do
        landing = create_session(channel: "paid_search")
        converting = create_session(channel: "paid_search")
        create_conversion(session: converting, journey: [landing, converting])

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns warning when mismatch rate between thresholds" do
        # 1 mismatch out of 3 = 33%
        2.times do
          s = create_session(channel: "organic_search")
          create_conversion(session: s, journey: [s])
        end

        landing = create_session(channel: "paid_search")
        converting = create_session(channel: "direct")
        create_conversion(session: converting, journey: [landing, converting])

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 33.3, result[:value], 0.1
      end

      test "returns critical when mismatch rate above critical" do
        # 3 mismatches out of 4 = 75%
        s = create_session(channel: "organic_search")
        create_conversion(session: s, journey: [s])

        3.times do
          landing = create_session(channel: "paid_search")
          converting = create_session(channel: "referral")
          create_conversion(session: converting, journey: [landing, converting])
        end

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 75.0, result[:value]
      end

      test "returns healthy with zero conversions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "handles single-session journey gracefully" do
        s = create_session(channel: "paid_search")
        create_conversion(session: s, journey: [s])

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "attribution_mismatch", result[:check_name]
        assert_in_delta 25.0, result[:warning_threshold]
        assert_in_delta 50.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)
      def check = DataIntegrity::Checks::AttributionMismatch.new(account)

      def create_session(channel:)
        account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: 1.day.ago,
          channel: channel
        )
      end

      def create_conversion(session:, journey:)
        account.conversions.create!(
          visitor: visitor,
          session_id: session.id,
          conversion_type: "test",
          converted_at: 1.day.ago + 30.minutes,
          journey_session_ids: journey.map(&:id)
        )
      end
    end
  end
end
