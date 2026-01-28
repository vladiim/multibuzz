# frozen_string_literal: true

require "test_helper"

module UnifiedFeed
  class QueryServiceTest < ActiveSupport::TestCase
    test "returns feed items sorted by occurred_at descending" do
      result = service.call

      timestamps = result.map(&:occurred_at)
      assert_equal timestamps.sort.reverse, timestamps
    end

    test "includes events as :event feed type" do
      result = service.call

      event_items = result.select(&:event?)
      assert event_items.any?, "expected at least one event feed item"
      assert event_items.all? { |item| item.record.is_a?(Event) }
    end

    test "includes conversions as :conversion feed type" do
      result = service.call

      conversion_items = result.select(&:conversion?)
      assert conversion_items.any?, "expected at least one conversion feed item"
      assert conversion_items.all? { |item| item.record.is_a?(Conversion) }
    end

    test "includes identities as :identify feed type" do
      result = service.call

      identify_items = result.select(&:identify?)
      assert identify_items.any?, "expected at least one identify feed item"
      assert identify_items.all? { |item| item.record.is_a?(Identity) }
    end

    test "includes sessions as :session feed type" do
      result = service.call

      session_items = result.select(&:session?)
      assert session_items.any?, "expected at least one session feed item"
      assert session_items.all? { |item| item.record.is_a?(Session) }
    end

    test "includes visitors as :visitor feed type" do
      result = service.call

      visitor_items = result.select(&:visitor?)
      assert visitor_items.any?, "expected at least one visitor feed item"
      assert visitor_items.all? { |item| item.record.is_a?(Visitor) }
    end

    test "respects limit" do
      result = service(limit: 3).call

      assert_operator result.size, :<=, 3
    end

    test "filters events and conversions by test mode" do
      result = test_service.call

      event_items = result.select(&:event?)
      conversion_items = result.select(&:conversion?)

      event_items.each do |item|
        assert item.record.is_test, "expected only test events"
      end

      conversion_items.each do |item|
        assert item.record.is_test, "expected only test conversions"
      end
    end

    test "filters sessions visitors and identities by test mode" do
      result = test_service.call

      session_items = result.select(&:session?)
      visitor_items = result.select(&:visitor?)
      identify_items = result.select(&:identify?)

      session_items.each do |item|
        assert item.record.is_test, "expected only test sessions"
      end

      visitor_items.each do |item|
        assert item.record.is_test, "expected only test visitors"
      end

      identify_items.each do |item|
        assert item.record.is_test, "expected only test identities"
      end
    end

    test "scopes to account - no cross-tenant leakage" do
      result = service.call

      result.each do |item|
        assert_equal account.id, item.record.account_id,
          "feed item #{item.feed_type} belongs to wrong account"
      end
    end

    test "returns empty array for account with no data" do
      empty_account = Account.create!(name: "Empty", slug: "empty-#{SecureRandom.hex(4)}")
      result = UnifiedFeed::QueryService.new(empty_account).call

      assert_equal [], result
    end

    test "each feed item has occurred_at and prefix_id" do
      result = service.call

      result.each do |item|
        assert_not_nil item.occurred_at, "#{item.feed_type} missing occurred_at"
        assert_not_nil item.prefix_id, "#{item.feed_type} missing prefix_id"
      end
    end

    private

    def service(limit: 100)
      @service = UnifiedFeed::QueryService.new(account, limit: limit)
    end

    def test_service
      @test_service ||= UnifiedFeed::QueryService.new(account, test_only: true)
    end

    def account
      @account ||= accounts(:one)
    end
  end
end
