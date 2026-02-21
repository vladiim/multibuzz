# frozen_string_literal: true

require "test_helper"

module Dashboard
  module Scopes
    class SessionsScopeTest < ActiveSupport::TestCase
      test "excludes suspect sessions from results" do
        result = scope.call

        session_ids = result.pluck(:session_id)

        assert_not_includes session_ids, "sess_suspect_ghost"
      end

      test "includes non-suspect sessions" do
        result = scope.call

        session_ids = result.pluck(:session_id)

        assert_includes session_ids, "sess_abc123xyz789"
      end

      test "suspect filtering combines with channel filter" do
        result = scope(channels: [ Channels::PAID_SEARCH ]).call

        assert_predicate result.where(suspect: true).count, :zero?
      end

      test "suspect filtering combines with date range" do
        result = scope(date_range: "7d").call

        assert_predicate result.where(suspect: true).count, :zero?
      end

      private

      def scope(date_range: "30d", channels: Channels::ALL)
        Dashboard::Scopes::SessionsScope.new(
          account: account,
          date_range: Dashboard::DateRangeParser.new(date_range),
          channels: channels
        )
      end

      def account
        @account ||= accounts(:one)
      end
    end
  end
end
