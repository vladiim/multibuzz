# frozen_string_literal: true

require "test_helper"

module Dashboard
  class CsvExportServiceTest < ActiveSupport::TestCase
    setup do
      AttributionCredit.delete_all
      Conversion.where(account: account).delete_all
    end

    # ==========================================
    # CSV structure tests
    # ==========================================

    test "returns CSV string with correct headers" do
      csv = parse_csv(service.call)

      assert_equal expected_headers, csv.headers
    end

    test "returns headers-only CSV when no data" do
      csv = parse_csv(service.call)

      assert_equal expected_headers, csv.headers
      assert_equal 0, csv.size
    end

    # ==========================================
    # Data accuracy tests
    # ==========================================

    test "rows contain denormalized credit, conversion, and model data" do
      create_full_credit

      csv = parse_csv(service.call)

      assert_equal 1, csv.size
      row = csv.first

      assert_equal 5.days.ago.to_date.to_s, row["date"]
      assert_equal "conversion", row["type"]
      assert_equal "purchase", row["name"]
      assert_equal "sales", row["funnel"]
      assert_equal first_touch_model.name, row["attribution_model"]
      assert_equal "first_touch", row["algorithm"]
      assert_equal Channels::PAID_SEARCH, row["channel"]
      assert_equal "1.0", row["credit"]
      assert_equal "199.99", row["revenue"]
      assert_equal "100.0", row["revenue_credit"]
      assert_equal "USD", row["currency"]
      assert_equal "google", row["utm_source"]
      assert_equal "cpc", row["utm_medium"]
      assert_equal "summer_sale", row["utm_campaign"]
      assert_equal "true", row["is_acquisition"]
      assert_equal '{"plan":"pro"}', row["properties"]
    end

    test "type column is always conversion" do
      create_full_credit
      create_minimal_credit

      csv = parse_csv(service.call)

      csv.each { |row| assert_equal "conversion", row["type"] }
    end

    # ==========================================
    # Nil value handling
    # ==========================================

    test "handles nil revenue, UTM params, funnel, and properties" do
      create_minimal_credit

      csv = parse_csv(service.call)
      row = csv.first

      assert_nil row["revenue"]
      assert_nil row["revenue_credit"]
      assert_nil row["utm_source"]
      assert_nil row["utm_medium"]
      assert_nil row["utm_campaign"]
      assert_nil row["funnel"]
      assert_equal "{}", row["properties"]
    end

    # ==========================================
    # Filter tests
    # ==========================================

    test "respects date range filter" do
      create_credit_at(5.days.ago)
      create_credit_at(35.days.ago)

      csv = parse_csv(service(date_range: "7d").call)

      assert_equal 1, csv.size
    end

    test "respects channel filter" do
      create_credit(channel: Channels::PAID_SEARCH)
      create_credit(channel: Channels::EMAIL)

      csv = parse_csv(service(channels: [ Channels::PAID_SEARCH ]).call)

      assert_equal 1, csv.size
      assert_equal Channels::PAID_SEARCH, csv.first["channel"]
    end

    test "respects attribution model filter" do
      other_model = account.attribution_models.create!(
        name: "Other Model",
        algorithm: :linear,
        is_active: true
      )
      create_credit(model: first_touch_model)
      create_credit(model: other_model)

      csv = parse_csv(service(models: [ first_touch_model ]).call)

      assert_equal 1, csv.size
      assert_equal first_touch_model.name, csv.first["attribution_model"]
    end

    test "respects test mode" do
      create_credit(is_test: false)
      create_credit(is_test: true)

      csv = parse_csv(service(test_mode: true).call)

      assert_equal 1, csv.size
    end

    # ==========================================
    # Multi-account isolation
    # ==========================================

    test "cannot access other account's data" do
      create_credit
      other_account = accounts(:two)
      other_model = other_account.attribution_models.first
      other_conversion = other_account.conversions.create!(
        visitor: visitors(:three),
        conversion_type: "signup",
        converted_at: Time.current
      )
      other_account.attribution_credits.create!(
        conversion: other_conversion,
        attribution_model: other_model,
        session_id: 999,
        channel: Channels::DIRECT,
        credit: 1.0
      )

      csv = parse_csv(service.call)

      assert_equal 1, csv.size
      channels = csv.map { |row| row["channel"] }

      assert_not_includes channels, Channels::DIRECT
    end

    private

    def expected_headers
      %w[
        date type name funnel attribution_model algorithm
        channel credit revenue revenue_credit currency
        utm_source utm_medium utm_campaign is_acquisition properties
      ]
    end

    def service(date_range: "30d", models: nil, channels: Channels::ALL, test_mode: false)
      models ||= [ first_touch_model ]
      filter_params = {
        date_range: date_range,
        models: models,
        channels: channels,
        conversion_filters: [],
        test_mode: test_mode
      }
      Dashboard::CsvExportService.new(account, filter_params)
    end

    def account
      @account ||= accounts(:one)
    end

    def first_touch_model
      @first_touch_model ||= attribution_models(:first_touch)
    end

    def parse_csv(csv_string)
      CSV.parse(csv_string, headers: true)
    end

    def create_full_credit
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        identity: identities(:one),
        conversion_type: "purchase",
        revenue: 199.99,
        currency: "USD",
        converted_at: 5.days.ago,
        funnel: "sales",
        is_acquisition: true,
        properties: { plan: "pro" }
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        revenue_credit: 100.0,
        utm_source: "google",
        utm_medium: "cpc",
        utm_campaign: "summer_sale",
        is_test: false
      )
    end

    def create_minimal_credit
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "signup",
        converted_at: 5.days.ago
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 1,
        channel: Channels::ORGANIC_SEARCH,
        credit: 1.0,
        is_test: false
      )
    end

    def create_credit_at(time)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: time
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0,
        is_test: false
      )
    end

    def create_credit(channel: Channels::PAID_SEARCH, model: nil, is_test: false)
      model ||= first_touch_model
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        is_test: is_test
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: model,
        session_id: rand(100..999),
        channel: channel,
        credit: 1.0,
        is_test: is_test
      )
    end
  end
end
