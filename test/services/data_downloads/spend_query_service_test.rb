# frozen_string_literal: true

require "test_helper"

module DataDownloads
  class SpendQueryServiceTest < ActiveSupport::TestCase
    # ==========================================
    # Result shape
    # ==========================================

    test "returns a hash with :data and :meta keys" do
      result = call_service

      assert_kind_of Array, result[:data]
      assert_kind_of Hash, result[:meta]
    end

    test "meta includes pagination fields" do # rubocop:disable Minitest/MultipleAssertions
      result = call_service

      assert_kind_of Integer, result[:meta][:total_count]
      assert_equal 1, result[:meta][:page]
      assert_kind_of Integer, result[:meta][:per_page]
      assert_kind_of Integer, result[:meta][:total_pages]
    end

    test "data row has the documented fields" do # rubocop:disable Minitest/MultipleAssertions
      result = call_service
      row = result[:data].find { |r| r[:campaign_name] == "Brand Search" && r[:spend_date] == Date.current.to_s }

      assert row, "expected the Brand Search row in result"
      assert_equal "paid_search", row[:channel]
      assert_equal "google_ads", row[:platform]
      assert_equal "SEARCH", row[:campaign_type]
      assert_equal "DESKTOP", row[:device]
      assert_equal 14, row[:spend_hour]
      assert_in_delta 12.4, row[:spend], 0.001
      assert_equal "USD", row[:currency]
      assert_equal 5000, row[:impressions]
      assert_equal 250, row[:clicks]
      assert_in_delta 10.0, row[:platform_conversions], 0.001
      assert_in_delta 50.0, row[:platform_conversion_value], 0.001
      assert_kind_of Hash, row[:metadata]
    end

    test "metadata is a Hash (not a JSON string)" do
      tagged = AdSpendRecord.create!(
        account: account,
        ad_platform_connection: ad_platform_connections(:google_ads),
        spend_date: Date.current,
        spend_hour: 9,
        channel: Channels::PAID_SEARCH,
        platform_campaign_id: "cmp_tagged",
        campaign_name: "Tagged Campaign",
        spend_micros: 1_000_000,
        currency: "USD",
        impressions: 10,
        clicks: 1,
        is_test: false,
        metadata: { "location" => "Sydney" }
      )

      result = call_service
      row = result[:data].find { |r| r[:campaign_name] == tagged.campaign_name }

      assert_equal({ "location" => "Sydney" }, row[:metadata])
    end

    # ==========================================
    # Filters
    # ==========================================

    test "respects date_range" do
      old_row = AdSpendRecord.create!(
        account: account,
        ad_platform_connection: ad_platform_connections(:google_ads),
        spend_date: 90.days.ago.to_date,
        spend_hour: 1,
        channel: Channels::PAID_SEARCH,
        platform_campaign_id: "cmp_old",
        campaign_name: "Old Campaign",
        spend_micros: 1_000_000,
        currency: "USD",
        impressions: 1, clicks: 1, is_test: false
      )

      result = call_service(date_range: "7d")

      assert result[:data].none? { |r| r[:campaign_name] == old_row.campaign_name }
    end

    test "respects channels filter" do
      result = call_service(channels: [ Channels::PAID_SEARCH ])

      assert result[:data].all? { |r| r[:channel] == Channels::PAID_SEARCH }
    end

    test "test mode true returns only test rows" do
      result = call_service(test_mode: true)
      names = result[:data].map { |r| r[:campaign_name] }.uniq

      assert_equal [ "Test Campaign" ], names
    end

    test "test mode false excludes test rows" do
      result = call_service(test_mode: false)

      assert result[:data].none? { |r| r[:campaign_name] == "Test Campaign" }
    end

    # ==========================================
    # Pagination
    # ==========================================

    test "honours per_page" do
      result = call_service(per_page: 1)

      assert_equal 1, result[:data].size
      assert_equal 1, result[:meta][:per_page]
    end

    test "clamps per_page over 1000 to 1000" do
      result = call_service(per_page: 5000)

      assert_equal 1000, result[:meta][:per_page]
    end

    test "clamps per_page under 1 to 1" do
      result = call_service(per_page: 0)

      assert_equal 1, result[:meta][:per_page]
    end

    test "total_pages reflects total_count / per_page" do
      result = call_service(per_page: 1)

      assert_equal result[:meta][:total_count], result[:meta][:total_pages]
    end

    test "page beyond range returns empty data with correct meta" do
      result = call_service(page: 999)

      assert_equal [], result[:data]
      assert_equal 999, result[:meta][:page]
      assert_operator result[:meta][:total_count], :>, 0
    end

    # ==========================================
    # Account isolation
    # ==========================================

    test "never returns another account's rows" do
      result = call_service

      assert result[:data].none? { |r| r[:campaign_name] == "Beta Search" },
        "should not leak account two's data"
    end

    # ==========================================
    # Empty result
    # ==========================================

    test "returns empty data + zero meta when no rows match" do
      AdSpendRecord.where(account: account).delete_all

      result = call_service

      assert_equal [], result[:data]
      assert_equal 0, result[:meta][:total_count]
      assert_equal 0, result[:meta][:total_pages]
    end

    private

    def account = @account ||= accounts(:one)

    def call_service(**overrides)
      DataDownloads::SpendQueryService.new(account, default_params.merge(overrides)).call
    end

    def default_params
      { date_range: "30d", channels: Channels::ALL, test_mode: false, page: 1, per_page: 100 }
    end
  end
end
