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
      csv = export_and_parse

      assert_equal expected_headers, csv.headers
    end

    test "returns headers-only CSV when no data" do
      csv = export_and_parse

      assert_equal expected_headers, csv.headers
      assert_equal 0, csv.size
    end

    test "fires feature_csv_exported lifecycle event after writing" do
      export_and_parse

      tracked = Lifecycle::Tracker.recorded_events.find { |e| e[:name] == "feature_csv_exported" }

      assert(tracked, "expected feature_csv_exported to be recorded")
      assert_equal "attribution", tracked[:properties][:export_type]
    end

    # ==========================================
    # Data accuracy tests
    # ==========================================

    test "rows contain denormalized credit, conversion, and model data" do
      create_full_credit

      csv = export_and_parse

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
      assert_equal '{"plan": "pro"}', row["properties"]
      assert_equal AttributionAlgorithms::FIRST_TOUCH, row["journey_position"]
      assert_equal "1", row["touchpoint_index"]
      assert_equal "1", row["journey_length"]
      assert_equal "5", row["days_to_conversion"]
    end

    test "type column is always conversion" do
      create_full_credit
      create_minimal_credit

      csv = export_and_parse

      csv.each { |row| assert_equal "conversion", row["type"] }
    end

    # ==========================================
    # Nil value handling
    # ==========================================

    test "handles nil revenue, UTM params, funnel, and properties" do
      create_minimal_credit

      csv = export_and_parse
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

      csv = export_and_parse(service(date_range: "7d"))

      assert_equal 1, csv.size
    end

    test "respects channel filter" do
      create_credit(channel: Channels::PAID_SEARCH)
      create_credit(channel: Channels::EMAIL)

      csv = export_and_parse(service(channels: [ Channels::PAID_SEARCH ]))

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

      csv = export_and_parse(service(models: [ first_touch_model ]))

      assert_equal 1, csv.size
      assert_equal first_touch_model.name, csv.first["attribution_model"]
    end

    test "respects test mode" do
      create_credit(is_test: false)
      create_credit(is_test: true)

      csv = export_and_parse(service(test_mode: true))

      assert_equal 1, csv.size
    end

    # ==========================================
    # Journey position tests
    # ==========================================

    test "single touchpoint journey has first_touch position" do
      session = create_journey_session(started_at: 10.days.ago)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        journey_session_ids: [ session.id ]
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: session.id,
        channel: Channels::PAID_SEARCH,
        credit: 1.0
      )

      csv = export_and_parse
      row = csv.first

      assert_equal AttributionAlgorithms::FIRST_TOUCH, row["journey_position"]
      assert_equal "1", row["touchpoint_index"]
      assert_equal "1", row["journey_length"]
    end

    test "two touchpoint journey: first is first_touch, second is last_touch" do
      s1 = create_journey_session(started_at: 10.days.ago)
      s2 = create_journey_session(started_at: 5.days.ago)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 3.days.ago,
        journey_session_ids: [ s1.id, s2.id ]
      )
      [ s1, s2 ].each do |s|
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: first_touch_model,
          session_id: s.id,
          channel: Channels::PAID_SEARCH,
          credit: 0.5
        )
      end

      csv = export_and_parse
      rows = csv.sort_by { |r| r["touchpoint_index"].to_i }

      assert_equal AttributionAlgorithms::FIRST_TOUCH, rows[0]["journey_position"]
      assert_equal AttributionAlgorithms::LAST_TOUCH, rows[1]["journey_position"]
      assert_equal "2", rows[0]["journey_length"]
      assert_equal "2", rows[1]["journey_length"]
    end

    test "three touchpoint journey: middle touchpoints are assisted" do
      s1 = create_journey_session(started_at: 15.days.ago)
      s2 = create_journey_session(started_at: 10.days.ago)
      s3 = create_journey_session(started_at: 5.days.ago)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 3.days.ago,
        journey_session_ids: [ s1.id, s2.id, s3.id ]
      )
      [ s1, s2, s3 ].each do |s|
        account.attribution_credits.create!(
          conversion: conversion,
          attribution_model: first_touch_model,
          session_id: s.id,
          channel: Channels::PAID_SEARCH,
          credit: 0.33
        )
      end

      csv = export_and_parse
      rows = csv.sort_by { |r| r["touchpoint_index"].to_i }

      assert_equal AttributionAlgorithms::FIRST_TOUCH, rows[0]["journey_position"]
      assert_equal AttributionAlgorithms::ASSISTED, rows[1]["journey_position"]
      assert_equal AttributionAlgorithms::LAST_TOUCH, rows[2]["journey_position"]
      assert_equal "3", rows[0]["journey_length"]
    end

    test "days_to_conversion calculated from session start to conversion" do
      session = create_journey_session(started_at: 10.days.ago)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 3.days.ago,
        journey_session_ids: [ session.id ]
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: session.id,
        channel: Channels::PAID_SEARCH,
        credit: 1.0
      )

      csv = export_and_parse
      row = csv.first

      assert_equal "7", row["days_to_conversion"]
    end

    test "nil journey_session_ids returns nil journey columns" do
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        journey_session_ids: nil
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0
      )

      csv = export_and_parse
      row = csv.first

      assert_nil row["journey_position"]
      assert_nil row["touchpoint_index"]
      assert_nil row["journey_length"]
      assert_nil row["days_to_conversion"]
    end

    test "empty journey_session_ids returns nil journey columns" do
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        journey_session_ids: []
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: rand(100..999),
        channel: Channels::PAID_SEARCH,
        credit: 1.0
      )

      csv = export_and_parse
      row = csv.first

      assert_nil row["journey_position"]
      assert_nil row["touchpoint_index"]
      assert_nil row["journey_length"]
      assert_nil row["days_to_conversion"]
    end

    test "credit session_id not in journey returns nil journey columns" do
      session = create_journey_session(started_at: 10.days.ago)
      conversion = account.conversions.create!(
        visitor: visitors(:one),
        conversion_type: "purchase",
        converted_at: 5.days.ago,
        journey_session_ids: [ session.id ]
      )
      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: 999_999,
        channel: Channels::PAID_SEARCH,
        credit: 1.0
      )

      csv = export_and_parse
      row = csv.first

      assert_nil row["journey_position"]
      assert_nil row["touchpoint_index"]
    end

    # ==========================================
    # SQL-specific edge cases
    # ==========================================

    test "does not use find_in_batches or preload_journey_sessions" do
      source = File.read(Rails.root.join("app/services/dashboard/csv_export_service.rb"))

      assert_not source.include?("find_in_batches"), "Should not use find_in_batches"
      assert_not source.include?("preload_journey_sessions"), "Should not use preload_journey_sessions"
    end

    test "handles all algorithm enum values" do
      algorithms = { linear: 2, time_decay: 3, u_shaped: 4, markov_chain: 7, shapley_value: 8 }

      algorithms.each do |algo_name, _algo_val|
        model = account.attribution_models.create!(name: "#{algo_name}_test", algorithm: algo_name, is_active: true)
        create_credit(model: model)

        csv = export_and_parse(service(models: [ model ]))
        row = csv.first

        assert_equal algo_name.to_s, row["algorithm"], "Algorithm #{algo_name} should be labeled correctly"

        AttributionCredit.where(attribution_model: model).delete_all
        model.destroy!
      end
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

      csv = export_and_parse

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
        journey_position touchpoint_index journey_length days_to_conversion
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

    def export_and_parse(svc = service)
      file = Tempfile.new([ "export_test", ".csv" ])
      svc.write_to(file.path)
      CSV.parse(File.read(file.path), headers: true)
    ensure
      file&.close!
    end

    def create_full_credit
      session = create_journey_session(started_at: 10.days.ago)

      conversion = account.conversions.create!(
        visitor: visitors(:one),
        identity: identities(:one),
        conversion_type: "purchase",
        revenue: 199.99,
        currency: "USD",
        converted_at: 5.days.ago,
        funnel: "sales",
        is_acquisition: true,
        properties: { plan: "pro" },
        journey_session_ids: [ session.id ]
      )

      account.attribution_credits.create!(
        conversion: conversion,
        attribution_model: first_touch_model,
        session_id: session.id,
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

    def create_journey_session(started_at: 10.days.ago)
      account.sessions.create!(
        visitor: visitors(:one),
        session_id: "sess_csv_test_#{SecureRandom.hex(4)}",
        started_at: started_at,
        channel: Channels::PAID_SEARCH
      )
    end
  end
end
