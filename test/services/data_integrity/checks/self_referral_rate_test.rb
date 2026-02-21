# frozen_string_literal: true

require "test_helper"

module DataIntegrity
  module Checks
    class SelfReferralRateTest < ActiveSupport::TestCase
      setup do
        account.sessions.destroy_all
      end

      test "returns healthy when self-referral rate below warning" do
        create_referral_session(referrer: "https://google.com", page_url: "https://mysite.com/page")
        create_referral_session(referrer: "https://facebook.com", page_url: "https://mysite.com/page")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "returns warning when self-referral rate between thresholds" do
        # 2 self-referral out of 8 referral sessions = 25%
        6.times { create_referral_session(referrer: "https://google.com", page_url: "https://mysite.com") }
        2.times { create_referral_session(referrer: "https://mysite.com/other", page_url: "https://mysite.com/page") }

        result = check.call

        assert_equal :warning, result[:status]
        assert_in_delta 25.0, result[:value]
      end

      test "returns critical when self-referral rate above critical" do
        # 3 self-referral out of 5 = 60%
        2.times { create_referral_session(referrer: "https://google.com", page_url: "https://mysite.com") }
        3.times { create_referral_session(referrer: "https://mysite.com/other", page_url: "https://mysite.com/page") }

        result = check.call

        assert_equal :critical, result[:status]
        assert_in_delta 60.0, result[:value]
      end

      test "returns healthy with zero referral sessions" do
        result = check.call

        assert_equal :healthy, result[:status]
        assert_in_delta 0.0, result[:value]
      end

      test "ignores sessions without referrer" do
        create_session_without_referrer
        create_referral_session(referrer: "https://google.com", page_url: "https://mysite.com")

        result = check.call

        assert_equal :healthy, result[:status]
        assert_equal 1, result[:details][:referral_sessions]
      end

      test "normalizes www prefix when comparing hosts" do
        create_referral_session(referrer: "https://www.mysite.com", page_url: "https://mysite.com/page")

        result = check.call

        assert_operator result[:value], :>, 0, "Should detect www.mysite.com as self-referral for mysite.com"
      end

      test "returns correct check metadata" do
        result = check.call

        assert_equal "self_referral_rate", result[:check_name]
        assert_in_delta 15.0, result[:warning_threshold]
        assert_in_delta 40.0, result[:critical_threshold]
      end

      private

      def account = @account ||= accounts(:one)
      def visitor = @visitor ||= visitors(:one)
      def check = DataIntegrity::Checks::SelfReferralRate.new(account)

      def create_referral_session(referrer:, page_url:)
        session = account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: 1.day.ago,
          initial_referrer: referrer,
          channel: "referral"
        )
        account.events.create!(
          visitor: visitor,
          session: session,
          event_type: "page_view",
          occurred_at: 1.day.ago + 1.minute,
          properties: { url: page_url }
        )
        session
      end

      def create_session_without_referrer
        account.sessions.create!(
          visitor: visitor,
          session_id: "sess_#{SecureRandom.hex(8)}",
          started_at: 1.day.ago,
          initial_referrer: nil,
          channel: "direct"
        )
      end
    end
  end
end
