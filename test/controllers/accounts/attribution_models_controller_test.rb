# frozen_string_literal: true

require "test_helper"

class Accounts::AttributionModelsControllerTest < ActionDispatch::IntegrationTest
  # --- Index ---

  test "index renders attribution models page" do
    sign_in

    get account_attribution_models_path

    assert_response :success
  end

  test "index shows custom model count for paid plans" do
    account.update!(plan: starter_plan)
    account.attribution_models.create!(name: "Custom 1", model_type: :custom, dsl_code: "test")
    sign_in

    get account_attribution_models_path

    assert_response :success
  end

  test "index requires authentication" do
    get account_attribution_models_path

    assert_redirected_to login_path
  end

  # --- Authorization ---

  test "member cannot access index" do
    sign_in_as_member

    get account_attribution_models_path

    assert_response :forbidden
  end

  test "member cannot access new" do
    account.update!(plan: starter_plan)
    sign_in_as_member

    get new_account_attribution_model_path

    assert_response :forbidden
  end

  test "member cannot create model" do
    account.update!(plan: starter_plan)
    sign_in_as_member

    post account_attribution_models_path, params: {
      attribution_model: { name: "My Model", dsl_code: "test" }
    }

    assert_response :forbidden
  end

  test "member cannot edit model" do
    sign_in_as_member
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    get edit_account_attribution_model_path(model)

    assert_response :forbidden
  end

  test "member cannot update model" do
    sign_in_as_member
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    patch account_attribution_model_path(model), params: {
      attribution_model: { lookback_days: 60 }
    }

    assert_response :forbidden
  end

  test "member cannot destroy model" do
    sign_in_as_member
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test"
    )

    delete account_attribution_model_path(model)

    assert_response :forbidden
  end

  test "member cannot set default" do
    sign_in_as_member
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test"
    )

    post set_default_account_attribution_model_path(model)

    assert_response :forbidden
  end

  test "admin can access index" do
    sign_in_as_admin

    get account_attribution_models_path

    assert_response :success
  end

  # --- New ---

  test "new shows form for custom model" do
    account.update!(plan: starter_plan)
    sign_in

    get new_account_attribution_model_path

    assert_response :success
  end

  test "new redirects free users" do
    account.update!(plan: free_plan)
    sign_in

    get new_account_attribution_model_path

    assert_redirected_to account_attribution_models_path
  end

  test "new redirects when at limit" do
    account.update!(plan: starter_plan)
    3.times { |i| account.attribution_models.create!(name: "Custom #{i}", model_type: :custom, dsl_code: "test") }
    sign_in

    get new_account_attribution_model_path

    assert_redirected_to account_attribution_models_path
  end

  # --- Create ---

  test "create saves valid custom model" do
    account.update!(plan: starter_plan)
    sign_in
    valid_code = "within_window 30.days do\n  apply 1.0, to: touchpoints.first\nend"

    assert_difference "AttributionModel.count", 1 do
      post account_attribution_models_path, params: {
        attribution_model: { name: "My Model", dsl_code: valid_code }
      }
    end

    assert_redirected_to account_attribution_models_path
  end

  test "create rejects invalid AML code" do
    account.update!(plan: starter_plan)
    sign_in
    invalid_code = 'system("rm -rf /")'

    assert_no_difference "AttributionModel.count" do
      post account_attribution_models_path, params: {
        attribution_model: { name: "Evil Model", dsl_code: invalid_code }
      }
    end

    assert_response :unprocessable_entity
  end

  test "create enforces plan limits" do
    account.update!(plan: starter_plan)
    3.times { |i| account.attribution_models.create!(name: "Custom #{i}", model_type: :custom, dsl_code: "test") }
    sign_in

    assert_no_difference "AttributionModel.count" do
      post account_attribution_models_path, params: {
        attribution_model: { name: "Over Limit", dsl_code: "test" }
      }
    end

    assert_redirected_to account_attribution_models_path
  end

  # --- Edit ---

  test "edit shows form for custom model" do
    sign_in
    model = account.attribution_models.create!(
      name: "Custom Edit Test #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "within_window 30.days do\n  apply 1.0, to: touchpoints.first\nend"
    )

    get edit_account_attribution_model_path(model)

    assert_response :success
  end

  test "edit shows form for preset model" do
    sign_in
    model = account.attribution_models.create!(
      name: "First Touch Edit Test #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    get edit_account_attribution_model_path(model)

    assert_response :success
  end

  test "edit scopes to current account" do
    sign_in
    other_model = other_account.attribution_models.create!(
      name: "Other #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test"
    )

    get edit_account_attribution_model_path(other_model)

    assert_response :not_found
  end

  # --- Update ---

  test "update saves customized preset" do
    account.update!(plan: starter_plan)
    sign_in
    model = account.attribution_models.create!(
      name: "First Touch Update #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )
    new_code = "within_window 60.days do\n  apply 1.0, to: touchpoints.first\nend"

    patch account_attribution_model_path(model), params: {
      attribution_model: { dsl_code: new_code }
    }

    assert_redirected_to account_attribution_models_path
    model.reload
    assert_equal new_code, model.dsl_code
  end

  test "update validates AML code" do
    account.update!(plan: starter_plan)
    sign_in
    model = account.attribution_models.create!(
      name: "Custom Validate #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "within_window 30.days do\n  apply 1.0, to: touchpoints.first\nend"
    )

    patch account_attribution_model_path(model), params: {
      attribution_model: { dsl_code: 'system("bad")' }
    }

    assert_response :unprocessable_entity
  end

  test "update allows free users to change lookback_days" do
    account.update!(plan: free_plan)
    sign_in
    model = account.attribution_models.create!(
      name: "First Touch Free #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch,
      lookback_days: 30
    )

    patch account_attribution_model_path(model), params: {
      attribution_model: { lookback_days: 60 }
    }

    assert_redirected_to account_attribution_models_path
    model.reload
    assert_equal 60, model.lookback_days
  end

  # --- Destroy ---

  test "destroy removes custom model" do
    sign_in
    model = account.attribution_models.create!(
      name: "Custom Destroy #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test"
    )

    assert_difference "AttributionModel.count", -1 do
      delete account_attribution_model_path(model)
    end

    assert_redirected_to account_attribution_models_path
  end

  test "destroy prevents deleting preset models" do
    sign_in
    model = account.attribution_models.create!(
      name: "First Touch Destroy #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    assert_no_difference "AttributionModel.count" do
      delete account_attribution_model_path(model)
    end

    assert_redirected_to account_attribution_models_path
  end

  # --- Validate (JSON) ---

  test "validate returns success for valid code" do
    sign_in
    valid_code = "within_window 30.days do\n  apply 1.0, to: touchpoints.first\nend"

    post validate_account_attribution_models_path, params: { dsl_code: valid_code }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert json["valid"]
  end

  test "validate returns errors for invalid code" do
    sign_in
    invalid_code = 'system("rm -rf /")'

    post validate_account_attribution_models_path, params: { dsl_code: invalid_code }, as: :json

    assert_response :success
    json = JSON.parse(response.body)
    assert_not json["valid"]
    assert json["errors"].any?
  end

  # --- Reset ---

  test "reset clears dsl_code on preset model" do
    sign_in
    model = account.attribution_models.create!(
      name: "First Touch Reset #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch,
      dsl_code: "customized code"
    )

    post reset_account_attribution_model_path(model)

    assert_redirected_to edit_account_attribution_model_path(model)
    model.reload
    assert_nil model.dsl_code
  end

  # --- Set Default ---

  test "set_default sets model as account default" do
    sign_in
    model = account.attribution_models.create!(
      name: "Custom Default 1 #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test",
      is_default: false
    )
    other_model = account.attribution_models.create!(
      name: "Custom Default 2 #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test",
      is_default: true
    )

    post set_default_account_attribution_model_path(model)

    assert_redirected_to account_attribution_models_path
    model.reload
    other_model.reload
    assert model.is_default
    assert_not other_model.is_default
  end

  # --- Rerun ---

  test "rerun redirects when no stale conversions" do
    sign_in
    model = account.attribution_models.create!(
      name: "Rerun Test #{SecureRandom.hex(4)}",
      model_type: :custom,
      dsl_code: "test"
    )

    post rerun_account_attribution_model_path(model)

    assert_redirected_to account_attribution_models_path
    assert_match(/no.*conversion/i, flash[:alert])
  end

  test "rerun creates job when stale conversions exist within limit" do
    sign_in
    model = create_model_with_stale_credits

    assert_difference "::RerunJob.count", 1 do
      post rerun_account_attribution_model_path(model)
    end

    assert_redirected_to account_attribution_models_path
    assert_match(/rerun started/i, flash[:notice])
  end

  test "rerun shows confirmation when overage required" do
    # Starter has 1M rerun limit, so set usage near limit to trigger overage
    account.update!(plan: starter_plan, reruns_used_this_period: Billing::RERUN_LIMITS[Billing::PLAN_STARTER])
    sign_in
    model = create_model_with_stale_credits

    post rerun_account_attribution_model_path(model)

    assert_response :success
    assert_select "h2", /confirm/i
  end

  test "rerun proceeds with confirmed overage" do
    account.update!(
      plan: starter_plan,
      billing_status: :active,
      stripe_subscription_id: "sub_123",
      reruns_used_this_period: Billing::RERUN_LIMITS[Billing::PLAN_STARTER]
    )
    sign_in
    model = create_model_with_stale_credits

    assert_difference "::RerunJob.count", 1 do
      post rerun_account_attribution_model_path(model, confirm_overage: true)
    end

    assert_redirected_to account_attribution_models_path
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def user
    @user ||= users(:one)
  end

  def account
    @account ||= accounts(:one)
  end

  def other_account
    @other_account ||= accounts(:two)
  end

  def free_plan
    @free_plan ||= plans(:free)
  end

# --- Test (AML execution) ---

  test "test executes AML code and renders credit distribution" do
    sign_in
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    post test_account_attribution_model_path(model),
      params: { dsl_code: first_touch_code, journey_type: "four_touch" }

    assert_response :success
    assert_match(/100\.0%/, response.body)
    assert_match(/Organic Search/, response.body)
  end

  test "test renders error for invalid AML code" do
    sign_in
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    post test_account_attribution_model_path(model),
      params: { dsl_code: "invalid ruby {{{{", journey_type: "four_touch" }

    assert_response :success
    assert_match(/bg-red-50/, response.body)
  end

  test "test works with different journey types" do
    sign_in
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :linear
    )

    post test_account_attribution_model_path(model),
      params: { dsl_code: linear_code, journey_type: "two_touch" }

    assert_response :success
    assert_match(/50\.0%/, response.body)
    assert_match(/Paid Social/, response.body)
  end

  test "test requires authentication" do
    model = account.attribution_models.create!(
      name: "Test Model #{SecureRandom.hex(4)}",
      model_type: :preset,
      algorithm: :first_touch
    )

    post test_account_attribution_model_path(model),
      params: { dsl_code: first_touch_code }

    assert_redirected_to login_path
  end

  def starter_plan
    @starter_plan ||= plans(:starter)
  end

  def create_model_with_stale_credits
    model = account.attribution_models.create!(
      name: "Stale Model #{SecureRandom.hex(4)}",
      model_type: :custom,
      algorithm: :first_touch
    )
    model.update_columns(dsl_code: "test", version: 2)

    visitor = account.visitors.create!(visitor_id: "test-#{SecureRandom.hex(4)}")
    session = account.sessions.create!(
      visitor: visitor,
      session_id: "sess-#{SecureRandom.hex(4)}",
      started_at: Time.current,
      channel: "direct"
    )
    conversion = account.conversions.create!(
      visitor: visitor,
      session_id: session.id,
      conversion_type: "test",
      converted_at: Time.current
    )

    account.attribution_credits.create!(
      conversion: conversion,
      attribution_model: model,
      session_id: session.id,
      channel: "direct",
      credit: 1.0,
      model_version: 1
    )

    model
  end

  def first_touch_code
    <<~AML
      within_window 30.days do
        apply 1.0, to: touchpoints.first
      end
    AML
  end

  def linear_code
    <<~AML
      within_window 30.days do
        apply 1.0, to: touchpoints, distribute: :equal
      end
    AML
  end

  def sign_in_as_member
    post login_path, params: { email: member_user.email, password: "password123" }
  end

  def sign_in_as_admin
    post login_path, params: { email: admin_user.email, password: "password123" }
  end

  def member_user
    @member_user ||= users(:four)
  end

  def admin_user
    @admin_user ||= users(:three)
  end
end
