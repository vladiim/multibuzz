require "test_helper"

module DataIntegrity
  module Checks
    class GhostSessionRateTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when ghost rate below warning threshold" do
        create_sessions(total: 10, ghost: 1)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 10.0, result[:value]
      end

      test "returns warning when ghost rate between warning and critical" do
        create_sessions(total: 10, ghost: 3)

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 30.0, result[:value]
      end

      test "returns critical when ghost rate above critical threshold" do
        create_sessions(total: 10, ghost: 6)

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 60.0, result[:value]
      end

      test "returns healthy with zero sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
        assert_equal 0, result[:details][:total_sessions]
      end

      test "excludes test sessions" do
        create_session(ghost: true, is_test: true)
        create_session(ghost: false)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_equal 1, result[:details][:total_sessions]
      end

      test "excludes sessions older than 24 hours" do
        create_session(ghost: true, started_at: 25.hours.ago)
        create_session(ghost: false)

        result = check.call

        assert_equal :healthy, result[:status]
        assert_equal 1, result[:details][:total_sessions]
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "ghost_session_rate", result[:check_name]
        assert_in_delta 20.0, result[:warning_threshold]
        assert_in_delta 50.0, result[:critical_threshold]
      end

      private

      def account
        @account ||= accounts(:one)
      end

      def visitor
        @visitor ||= visitors(:one)
      end

      def check
        DataIntegrity::Checks::GhostSessionRate.new(account)
      end

      def create_sessions(total:, ghost:)
        ghost.times { create_session(ghost: true) }
        (total - ghost).times { create_session(ghost: false) }
      end

      def create_session(ghost:, is_test: false, started_at: 1.hour.ago)
        session = account.sessions.create!(
          visitor: visitor,
          session_id: "sess_test_#{SecureRandom.hex(8)}",
          started_at: started_at,
          is_test: is_test,
          initial_referrer: ghost ? nil : "https://google.com",
          initial_utm: ghost ? {} : { utm_source: "google" },
          click_ids: {}
        )

        unless ghost
          account.events.create!(
            visitor: visitor,
            session: session,
            event_type: "page_view",
            occurred_at: started_at + 1.minute,
            properties: { url: "https://example.com" }
          )
        end

        session
      end
    end
  end
end
