# frozen_string_literal: true

require "test_helper"

module DataDownloads
  class ConversionsQueryServiceTest < ActiveSupport::TestCase
    setup do
      account.attribution_credits.update_all(model_version: 1)
      [ recent_signup, recent_purchase ] # force creation before query
    end

    test "returns hash with data and meta keys" do
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

    test "row exposes documented fields" do # rubocop:disable Minitest/MultipleAssertions
      result = call_service
      row = result[:data].find { |r| r[:name] == "purchase_v2" }

      assert row, "expected a row for the seeded purchase"
      assert_equal "conversion", row[:type]
      assert_equal "purchase_v2", row[:name]
      assert_equal "paid_search", row[:channel]
      assert_kind_of String, row[:attribution_model]
      assert_kind_of String, row[:algorithm]
      assert_kind_of Numeric, row[:credit]
      assert_kind_of Hash, row[:properties]
    end

    test "respects test_mode flag" do
      test_credit = create_credit(is_test: true, channel: Channels::EMAIL)
      result = call_service(test_mode: true)
      names = result[:data].map { |r| r[:name] }.uniq

      assert_includes names, test_credit.conversion.conversion_type
      assert_predicate result[:data], :any?
    end

    test "live mode excludes test rows" do
      create_credit(is_test: true, channel: Channels::EMAIL)
      result = call_service(test_mode: false)

      assert result[:data].none? { |r| r[:channel] == Channels::EMAIL && r[:name].include?("test") }
    end

    test "channels filter narrows result" do
      result = call_service(channels: [ Channels::PAID_SEARCH ])

      assert result[:data].all? { |r| r[:channel] == Channels::PAID_SEARCH }
    end

    test "honours per_page" do
      result = call_service(per_page: 1)

      assert_operator result[:data].size, :<=, 1
    end

    test "clamps per_page over 1000" do
      result = call_service(per_page: 9999)

      assert_equal 1000, result[:meta][:per_page]
    end

    test "never leaks another account's credits" do
      result = call_service

      conversion_ids = result[:data].map { |r| r[:name] }

      assert_not_includes conversion_ids, "trial_start"
    end

    test "page beyond range returns empty data" do
      result = call_service(page: 999)

      assert_equal [], result[:data]
    end

    test "returns empty data and zero meta when no credits exist" do
      account.attribution_credits.destroy_all

      result = call_service

      assert_equal [], result[:data]
      assert_equal 0, result[:meta][:total_count]
      assert_equal 0, result[:meta][:total_pages]
    end

    test "journey_length reflects journey_session_ids size" do
      result = call_service
      row = result[:data].find { |r| r[:name] == "purchase_v2" }

      assert row
      assert_equal 2, row[:journey_length]
    end

    private

    def account = @account ||= accounts(:one)

    def call_service(**overrides)
      DataDownloads::ConversionsQueryService.new(account, default_params.merge(overrides)).call
    end

    def default_params
      { date_range: "30d", channels: Channels::ALL, test_mode: false, page: 1, per_page: 100 }
    end

    def recent_signup
      @recent_signup ||= create_conversion_with_credit(
        type: "signup_v2",
        channel: Channels::ORGANIC_SEARCH,
        revenue: nil,
        is_acquisition: false,
        attribution_model: account.attribution_models.find_by(algorithm: 0) || account.attribution_models.first
      )
    end

    def recent_purchase
      @recent_purchase ||= create_conversion_with_credit(
        type: "purchase_v2",
        channel: Channels::PAID_SEARCH,
        revenue: 99.99,
        is_acquisition: false,
        attribution_model: account.attribution_models.find_by(algorithm: 1) || account.attribution_models.first,
        journey_session_ids: [ sessions(:one).id, sessions(:two).id ]
      )
    end

    def create_conversion_with_credit(type:, channel:, revenue:, attribution_model:, is_acquisition: false, journey_session_ids: nil) # rubocop:disable Metrics/ParameterLists
      session = sessions(:one)
      conversion = account.conversions.create!(
        visitor: session.visitor,
        session_id: session.id,
        conversion_type: type,
        revenue: revenue,
        converted_at: 1.day.ago,
        properties: { "order_id" => "ORD-#{SecureRandom.hex(3)}" },
        is_acquisition: is_acquisition,
        currency: "USD",
        journey_session_ids: journey_session_ids || [ session.id ]
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: attribution_model,
        session_id: session.id,
        channel: channel,
        credit: 1.0,
        revenue_credit: revenue,
        model_version: 1
      )
      conversion
    end

    def create_credit(is_test:, channel:)
      session = sessions(:one)
      conversion = account.conversions.create!(
        visitor: session.visitor,
        session_id: session.id,
        conversion_type: "test_signup_#{SecureRandom.hex(2)}",
        converted_at: 1.day.ago,
        is_test: is_test,
        is_acquisition: false,
        currency: "USD",
        journey_session_ids: [ session.id ]
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: account.attribution_models.active.first,
        session_id: session.id,
        channel: channel,
        credit: 1.0,
        is_test: is_test,
        model_version: 1
      )
    end
  end
end
