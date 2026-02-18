# frozen_string_literal: true

require "test_helper"

class Dashboard::ExportsControllerTest < ActionDispatch::IntegrationTest
  setup do
    accounts(:one).update!(onboarding_progress: (1 << Account::Onboarding::ONBOARDING_STEPS.size) - 1)
  end

  test "returns CSV with attachment disposition" do
    sign_in
    post dashboard_export_path

    assert_response :success
    assert_equal "text/csv", response.content_type
    assert_match "attachment", response.headers["Content-Disposition"]
  end

  test "filename includes current date" do
    sign_in
    post dashboard_export_path

    assert_match "mbuzz-export-#{Date.current}.csv", response.headers["Content-Disposition"]
  end

  test "requires authentication" do
    post dashboard_export_path

    assert_response :redirect
  end

  test "dashboard export form has spinner and stimulus controller" do
    sign_in
    get dashboard_path

    assert_response :success
    assert_select "[data-controller~='export']"
    assert_select "#export-spinner"
  end

  test "broadcasts spinner removal after export" do
    sign_in

    assert_broadcasts("account_#{account.prefix_id}_exports", 1) do
      post dashboard_export_path
    end

    assert_response :success
  end

  test "returns 200 with empty data" do
    sign_in
    AttributionCredit.delete_all

    post dashboard_export_path

    assert_response :success
    csv = CSV.parse(response.body, headers: true)
    assert_equal 0, csv.size
  end

  test "includes all attribution models regardless of filter params" do
    sign_in
    create_credit(model: first_touch_model)
    create_credit(model: last_touch_model)

    post dashboard_export_path, params: { models: [first_touch_model.prefix_id] }

    csv = CSV.parse(response.body, headers: true)
    models = csv.map { |row| row["attribution_model"] }
    assert_includes models, first_touch_model.name
    assert_includes models, last_touch_model.name
  end

  test "includes all channels regardless of filter params" do
    sign_in
    create_credit(channel: Channels::PAID_SEARCH)
    create_credit(channel: Channels::EMAIL)

    post dashboard_export_path, params: { channels: [Channels::PAID_SEARCH] }

    csv = CSV.parse(response.body, headers: true)
    channels = csv.map { |row| row["channel"] }
    assert_includes channels, Channels::PAID_SEARCH
    assert_includes channels, Channels::EMAIL
  end

  test "ignores conversion filters" do
    sign_in
    create_credit(conversion_type: "purchase")
    create_credit(conversion_type: "signup")

    post dashboard_export_path, params: {
      conversion_filters: {
        "0" => { field: "conversion_type", operator: "is", values: ["purchase"] }
      }
    }

    csv = CSV.parse(response.body, headers: true)
    types = csv.map { |row| row["conversion_type"] }
    assert_includes types, "purchase"
    assert_includes types, "signup"
  end

  private

  def sign_in
    post login_path, params: { email: users(:one).email, password: "password123" }
  end

  def account
    @account ||= accounts(:one)
  end

  def first_touch_model
    @first_touch_model ||= attribution_models(:first_touch)
  end

  def last_touch_model
    @last_touch_model ||= attribution_models(:last_touch)
  end

  def create_credit(model: first_touch_model, channel: Channels::PAID_SEARCH, conversion_type: "purchase")
    conversion = account.conversions.create!(
      visitor: visitors(:one),
      conversion_type: conversion_type,
      converted_at: 5.days.ago,
      is_test: true
    )

    account.attribution_credits.create!(
      conversion: conversion,
      attribution_model: model,
      session_id: rand(100..999),
      channel: channel,
      credit: 1.0,
      is_test: true
    )
  end
end
