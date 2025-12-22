require "test_helper"

class AttributionModelTest < ActiveSupport::TestCase
  test "should belong to account" do
    assert_respond_to model, :account
    assert_equal accounts(:one), model.account
  end

  test "should have many attribution credits" do
    assert_respond_to model, :attribution_credits
  end

  test "should have prefixed id" do
    assert model.prefix_id.start_with?("attr_")
  end

  test "should require name" do
    model.name = nil
    assert_not model.valid?
    assert_includes model.errors[:name], "can't be blank"
  end

  test "should require unique name per account" do
    duplicate = AttributionModel.new(
      account: accounts(:one),
      name: "First Touch",
      model_type: :preset,
      algorithm: :first_touch
    )

    assert_not duplicate.valid?
    assert_includes duplicate.errors[:name], "has already been taken"
  end

  test "should allow same name for different accounts" do
    model_account_two = AttributionModel.new(
      account: accounts(:two),
      name: "First Touch",
      model_type: :preset,
      algorithm: :first_touch
    )

    assert model_account_two.valid?
  end

  test "should have preset model_type enum" do
    assert_respond_to model, :preset?
    assert_respond_to model, :custom?

    assert model.preset?
    assert_not model.custom?
  end

  test "should have algorithm enum for preset models" do
    assert_respond_to model, :first_touch?
    assert_respond_to model, :last_touch?
    assert_respond_to model, :linear?
    assert_respond_to model, :time_decay?
    assert_respond_to model, :u_shaped?
    assert_respond_to model, :participation?

    assert model.first_touch?
  end

  test "should scope active models" do
    assert_includes AttributionModel.active, model

    model.update!(is_active: false)
    assert_not_includes AttributionModel.active, model
  end

  test "should scope default model" do
    default = AttributionModel.default_for_account(accounts(:one))
    assert_equal model, default
    assert default.is_default?
  end

  test "should only allow one default per account" do
    model.update!(is_default: false)

    last_touch_model.update!(is_default: true)
    model.reload

    assert_not model.is_default?
    assert last_touch_model.is_default?
  end

  # --- Backfill Detection ---

  test "unattributed_conversions returns conversions without credits for this model" do
    test_model = create_test_model
    conversion = create_conversion_for(test_model.account)

    assert_includes test_model.unattributed_conversions, conversion
  end

  test "unattributed_conversions excludes conversions that have credits" do
    test_model = create_test_model
    conversion = create_conversion_for(test_model.account)
    create_credit_for(test_model, conversion)

    assert_not_includes test_model.unattributed_conversions, conversion
  end

  test "unattributed_conversions_count returns count of unattributed conversions" do
    test_model = create_test_model
    create_conversion_for(test_model.account)
    create_conversion_for(test_model.account)

    assert_equal 2, test_model.unattributed_conversions_count
  end

  test "has_unattributed_conversions? returns true when conversions exist without credits" do
    test_model = create_test_model
    create_conversion_for(test_model.account)

    assert test_model.has_unattributed_conversions?
  end

  test "has_unattributed_conversions? returns false when all conversions have credits" do
    test_model = create_test_model
    conversion = create_conversion_for(test_model.account)
    create_credit_for(test_model, conversion)

    assert_not test_model.has_unattributed_conversions?
  end

  test "needs_backfill? returns true when unattributed conversions exist" do
    test_model = create_test_model
    create_conversion_for(test_model.account)

    assert test_model.needs_backfill?
  end

  test "needs_backfill? returns false when no unattributed conversions" do
    test_model = create_test_model
    # No conversions at all
    assert_not test_model.needs_backfill?
  end

  test "pending_conversions_count includes both stale and unattributed" do
    test_model = create_test_model

    # Create unattributed conversion
    create_conversion_for(test_model.account)

    # Create stale credit (old version)
    stale_conversion = create_conversion_for(test_model.account)
    create_credit_for(test_model, stale_conversion, model_version: 0)
    test_model.update!(version: 2)

    # Should count both
    assert_equal 2, test_model.pending_conversions_count
  end

  test "needs_rerun? returns true when stale credits exist" do
    test_model = create_test_model
    conversion = create_conversion_for(test_model.account)
    create_credit_for(test_model, conversion, model_version: 0)
    test_model.update!(version: 2)

    assert test_model.needs_rerun?
  end

  test "needs_rerun? returns true when unattributed conversions exist" do
    test_model = create_test_model
    create_conversion_for(test_model.account)

    assert test_model.needs_rerun?
  end

  test "needs_rerun? returns false when fully attributed and up to date" do
    test_model = create_test_model
    conversion = create_conversion_for(test_model.account)
    create_credit_for(test_model, conversion, model_version: test_model.version)

    assert_not test_model.needs_rerun?
  end

  private

  def model
    @model ||= attribution_models(:first_touch)
  end

  def last_touch_model
    @last_touch_model ||= attribution_models(:last_touch)
  end

  def account
    @account ||= accounts(:one)
  end

  def create_test_model
    test_account = Account.create!(name: "Test Account #{SecureRandom.hex(4)}", slug: "test-#{SecureRandom.hex(4)}")
    AttributionModel.create!(
      account: test_account,
      name: "Test Model",
      model_type: :preset,
      algorithm: :first_touch,
      is_active: true,
      lookback_days: 30,
      version: 1
    )
  end

  def create_conversion_for(account)
    visitor = account.visitors.create!(visitor_id: SecureRandom.uuid)
    account.conversions.create!(
      visitor: visitor,
      conversion_type: "purchase",
      revenue: 100.0,
      converted_at: Time.current
    )
  end

  def create_credit_for(attribution_model, conversion, model_version: nil)
    AttributionCredit.create!(
      account: attribution_model.account,
      attribution_model: attribution_model,
      conversion: conversion,
      session_id: SecureRandom.uuid,
      channel: "direct",
      credit: 1.0,
      revenue_credit: conversion.revenue,
      model_version: model_version || attribution_model.version
    )
  end
end
