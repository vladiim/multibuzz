# frozen_string_literal: true

require "test_helper"

module DataDownloads
  class FunnelQueryServiceTest < ActiveSupport::TestCase
    setup do
      Session.where(account: account).update_all(channel: Channels::PAID_SEARCH)
      [ recent_visit, recent_event, recent_conversion ] # force creation
    end

    test "returns hash with data and meta keys" do
      result = call_service

      assert_kind_of Array, result[:data]
      assert_kind_of Hash, result[:meta]
    end

    test "result rows have a :type discriminator" do
      result = call_service
      types = result[:data].map { |r| r[:type] }.uniq.sort

      assert_includes types, FunnelStages::VISIT
      assert_includes types, FunnelStages::EVENT
      assert_includes types, FunnelStages::CONVERSION
    end

    test "visit rows have nil name" do
      result = call_service
      visit = result[:data].find { |r| r[:type] == FunnelStages::VISIT }

      assert visit
      assert_nil visit[:name]
    end

    test "event rows have event_type as name" do
      result = call_service
      event = result[:data].find { |r| r[:type] == FunnelStages::EVENT && r[:name] == "add_to_cart_v2" }

      assert event
    end

    test "conversion rows expose revenue + is_acquisition" do # rubocop:disable Minitest/MultipleAssertions
      result = call_service
      conversion = result[:data].find { |r| r[:type] == FunnelStages::CONVERSION && r[:name] == "purchase_v2" }

      assert conversion
      assert_in_delta 49.95, conversion[:revenue], 0.01
      assert_kind_of Hash, conversion[:properties]
      assert_includes [ true, false ], conversion[:is_acquisition]
    end

    test "rows include channel and UTM from the underlying session" do # rubocop:disable Minitest/MultipleAssertions
      result = call_service
      row = result[:data].first

      assert_equal Channels::PAID_SEARCH, row[:channel]
      assert row.key?(:utm_source)
      assert row.key?(:utm_medium)
      assert row.key?(:utm_campaign)
    end

    test "respects channels filter" do
      result = call_service(channels: [ Channels::EMAIL ])

      assert result[:data].all? { |r| r[:channel] == Channels::EMAIL }
    end

    test "respects funnel filter on events" do
      account.events.create!(
        visitor: recent_visit.visitor,
        session: recent_visit,
        event_type: "specific_funnel_event_v2",
        funnel: "checkout",
        occurred_at: 1.hour.ago,
        properties: { "url" => "/checkout" }
      )

      result = call_service(funnel: "checkout")
      types = result[:data].map { |r| r[:type] }.uniq

      # Funnel filter only narrows events; visits + conversions pass through
      assert_includes types, FunnelStages::EVENT
    end

    test "honours per_page" do
      result = call_service(per_page: 1)

      assert_operator result[:data].size, :<=, 1
    end

    test "clamps per_page over 1000" do
      result = call_service(per_page: 9999)

      assert_equal 1000, result[:meta][:per_page]
    end

    test "page beyond range returns empty data" do
      result = call_service(page: 999)

      assert_equal [], result[:data]
    end

    test "never returns other account's rows" do
      result = call_service
      session_ids = result[:data].map { |r| r[:session_id] }.compact

      account_session_ids = account.sessions.pluck(:id)

      session_ids.each do |sid|
        assert_includes account_session_ids, sid, "session #{sid} not in account one"
      end
    end

    test "returns empty data + zero meta when account has no rows" do
      account.events.destroy_all
      account.conversions.destroy_all
      account.sessions.destroy_all

      result = call_service

      assert_equal [], result[:data]
      assert_equal 0, result[:meta][:total_count]
    end

    private

    def account = @account ||= accounts(:one)

    def call_service(**overrides)
      DataDownloads::FunnelQueryService.new(account, default_params.merge(overrides)).call
    end

    def default_params
      { date_range: "30d", channels: Channels::ALL, test_mode: false, page: 1, per_page: 100, funnel: nil }
    end

    def recent_visit
      @recent_visit ||= account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_test_#{SecureRandom.hex(4)}",
        started_at: 2.hours.ago,
        channel: Channels::PAID_SEARCH,
        initial_utm: { "utm_source" => "google", "utm_medium" => "cpc", "utm_campaign" => "brand" },
        is_test: false
      )
    end

    def recent_event
      @recent_event ||= account.events.create!(
        visitor: recent_visit.visitor,
        session: recent_visit,
        event_type: "add_to_cart_v2",
        funnel: "checkout",
        occurred_at: 1.hour.ago,
        properties: { "url" => "/cart" }
      )
    end

    def recent_conversion
      @recent_conversion ||= account.conversions.create!(
        visitor: recent_visit.visitor,
        session_id: recent_visit.id,
        conversion_type: "purchase_v2",
        revenue: 49.95,
        converted_at: 30.minutes.ago,
        properties: { "order_id" => "ORD-#{SecureRandom.hex(3)}" },
        is_acquisition: false,
        currency: "USD",
        journey_session_ids: [ recent_visit.id ]
      )
    end
  end
end
