require "test_helper"

module DataIntegrity
  module Checks
    class SessionsPerConverterTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
        account.conversions.destroy_all
      end

      test "returns healthy when avg sessions per converter below warning" do
        v1 = create_visitor_with_sessions(3)
        v2 = create_visitor_with_sessions(2)
        create_conversion(visitor: v1)
        create_conversion(visitor: v2)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 2.5, result[:value]
      end

      test "returns warning when avg sessions per converter between thresholds" do
        v = create_visitor_with_sessions(8)
        create_conversion(visitor: v)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 8.0, result[:value]
      end

      test "returns critical when avg sessions per converter above critical" do
        v = create_visitor_with_sessions(20)
        create_conversion(visitor: v)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 20.0, result[:value]
      end

      test "returns healthy with zero conversions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "only counts sessions for visitors who have conversions" do
        v_converter = create_visitor_with_sessions(3)
        create_visitor_with_sessions(50) # non-converter, should be ignored
        create_conversion(visitor: v_converter)

        result = check.call

        assert_in_delta 3.0, result[:value]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "sessions_per_converter", result[:check_name]
        assert_in_delta 5.0, result[:warning_threshold]
        assert_in_delta 15.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def check = DataIntegrity::Checks::SessionsPerConverter.new(account)

      def create_visitor_with_sessions(count)
        v = account.visitors.create!(
          visitor_id: "vis_#{SecureRandom.hex(8)}",
          first_seen_at: 2.days.ago,
          last_seen_at: 1.day.ago
        )
        count.times do
          account.sessions.create!(
            visitor: v,
            session_id: "sess_#{SecureRandom.hex(8)}",
            started_at: 1.day.ago
          )
        end
        v
      end

      def create_conversion(visitor:)
        session = visitor.sessions.first
        account.conversions.create!(
          visitor: visitor,
          session_id: session.id,
          conversion_type: "test",
          converted_at: 1.day.ago + 30.minutes,
          journey_session_ids: [session.id]
        )
      end
    end
  end
end
