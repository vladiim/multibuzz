# frozen_string_literal: true

require "test_helper"

module Attribution
  module Markov
    class ConversionPathsQueryTest < ActiveSupport::TestCase
      setup do
        # Clear fixture conversions for clean test state
        account.conversions.destroy_all
      end

      test "should return channel paths from historical conversions" do
        create_conversion_with_sessions(%w[organic_search email paid_search])
        create_conversion_with_sessions(%w[paid_search])

        paths = query.call

        assert_equal 2, paths.size
        assert_includes paths, %w[organic_search email paid_search]
        assert_includes paths, %w[paid_search]
      end

      test "should order channels by session started_at within each path" do
        session1 = create_session(channel: "email", days_ago: 5)
        session2 = create_session(channel: "organic_search", days_ago: 10)
        session3 = create_session(channel: "paid_search", days_ago: 1)

        create_conversion(journey_session_ids: [session1.id, session2.id, session3.id])

        paths = query.call

        # Should be ordered: organic_search (10 days ago), email (5 days ago), paid_search (1 day ago)
        assert_equal [%w[organic_search email paid_search]], paths
      end

      test "should skip conversions with empty journey_session_ids" do
        create_conversion_with_sessions(%w[organic_search])
        create_conversion(journey_session_ids: [])

        paths = query.call

        assert_equal 1, paths.size
      end

      test "should skip sessions without channels" do
        session_with_channel = create_session(channel: "organic_search", days_ago: 5)
        session_without_channel = create_session(channel: nil, days_ago: 3)
        session_with_channel2 = create_session(channel: "paid_search", days_ago: 1)

        create_conversion(journey_session_ids: [
          session_with_channel.id,
          session_without_channel.id,
          session_with_channel2.id
        ])

        paths = query.call

        assert_equal [%w[organic_search paid_search]], paths
      end

      test "should return empty array when no conversions exist" do
        paths = query.call

        assert_empty paths
      end

      test "should only include conversions from the specified account" do
        create_conversion_with_sessions(%w[organic_search])

        other_account_query = ConversionPathsQuery.new(other_account)
        paths = other_account_query.call

        assert_empty paths
      end

      test "should handle duplicate channels in path" do
        create_conversion_with_sessions(%w[organic_search email organic_search paid_search])

        paths = query.call

        assert_equal [%w[organic_search email organic_search paid_search]], paths
      end

      test "should return paths for multiple conversions" do
        create_conversion_with_sessions(%w[organic_search email])
        create_conversion_with_sessions(%w[paid_search])
        create_conversion_with_sessions(%w[email paid_search])
        create_conversion_with_sessions(%w[organic_search paid_search])

        paths = query.call

        assert_equal 4, paths.size
      end

      private

      def query
        @query ||= ConversionPathsQuery.new(account)
      end

      def account
        @account ||= accounts(:one)
      end

      def other_account
        @other_account ||= accounts(:two)
      end

      def visitor
        @visitor ||= account.visitors.first || create_visitor
      end

      def create_visitor
        Visitor.create!(
          account: account,
          visitor_id: SecureRandom.hex(16)
        )
      end

      def create_conversion_with_sessions(channels)
        sessions = channels.each_with_index.map do |channel, index|
          create_session(channel: channel, days_ago: channels.size - index)
        end

        create_conversion(journey_session_ids: sessions.map(&:id))
      end

      def create_session(channel:, days_ago:)
        Session.create!(
          account: account,
          visitor: visitor,
          session_id: SecureRandom.hex(16),
          started_at: days_ago.days.ago,
          channel: channel
        )
      end

      def create_conversion(journey_session_ids:)
        Conversion.create!(
          account: account,
          visitor: visitor,
          session_id: 1,
          event_id: 1,
          conversion_type: "purchase",
          converted_at: Time.current,
          journey_session_ids: journey_session_ids
        )
      end
    end
  end
end
