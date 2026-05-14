# frozen_string_literal: true

require "test_helper"

class Admin::ConversionDispatchesControllerTest < ActionDispatch::IntegrationTest
  # --- Auth ---

  test "non-admin users are redirected with access denied" do
    sign_in_as(regular_user)

    get admin_conversion_dispatches_path

    assert_redirected_to root_path
  end

  test "unauthenticated users are redirected to login" do
    get admin_conversion_dispatches_path

    assert_redirected_to login_path
  end

  # --- Index ---

  test "admin sees the index with dispatch rows" do
    delivered_dispatch
    failed_dispatch
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path

    assert_response :success
    assert_select "[data-testid='dispatch-row']", count: 2
  end

  test "status filter narrows the list" do
    delivered_dispatch
    failed_dispatch
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path, params: { status: ConversionDispatch::Statuses::FAILED_PERMANENT }

    assert_select "[data-testid='dispatch-row']", count: 1
    assert_select "[data-testid='dispatch-row'][data-status='failed_permanent']"
  end

  test "account filter narrows by prefix_id" do
    delivered_dispatch
    other = other_account_dispatch
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path, params: { account_id: other.account.prefix_id }

    assert_select "[data-testid='dispatch-row']", count: 1
  end

  test "destination filter narrows by destination" do
    delivered_dispatch
    failed_dispatch
    other_dest = other_destination_dispatch
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path,
      params: { conversion_destination_id: other_dest.conversion_destination_id }

    assert_select "[data-testid='dispatch-row']", count: 1
  end

  test "date range filter narrows by created_at" do
    delivered_dispatch.update!(created_at: 10.days.ago)
    failed_dispatch.update!(created_at: 1.day.ago)
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path,
      params: { from: 3.days.ago.to_date.to_s, to: Date.current.to_s }

    assert_select "[data-testid='dispatch-row']", count: 1
  end

  test "default order is most recent first" do
    older = delivered_dispatch
    older.update!(created_at: 2.days.ago)
    newer = failed_dispatch
    newer.update!(created_at: 1.hour.ago)
    sign_in_as(admin_user)

    get admin_conversion_dispatches_path

    rows = response.body.scan(/data-prefix-id="(cdisp_[A-Za-z0-9]+)"/).flatten

    assert_equal [ newer.prefix_id, older.prefix_id ], rows
  end

  private

  def admin_user = @admin_user ||= users(:admin)
  def regular_user = @regular_user ||= users(:one)
  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
  def visitor = @visitor ||= visitors(:one)

  def destination
    @destination ||= ConversionDestination.create!(
      account: account, attribution_model: attribution_models(:last_touch),
      platform: "meta_capi", name: "Meta Primary",
      meta_pixel_id: "P_1", meta_access_token: "T_1", enabled: true,
      event_type_mapping: { "Lead" => { "meta_event" => "Lead" } }
    )
  end

  def other_destination
    @other_destination ||= ConversionDestination.create!(
      account: account, attribution_model: attribution_models(:last_touch),
      platform: "meta_capi", name: "Meta Secondary",
      meta_pixel_id: "P_2", meta_access_token: "T_2", enabled: true,
      event_type_mapping: { "Lead" => { "meta_event" => "Lead" } }
    )
  end

  def other_account_destination
    @other_account_destination ||= ConversionDestination.create!(
      account: other_account, attribution_model: attribution_models(:last_touch),
      platform: "meta_capi", name: "Other Account Meta",
      meta_pixel_id: "P_O", meta_access_token: "T_O", enabled: true,
      event_type_mapping: { "Lead" => { "meta_event" => "Lead" } }
    )
  end

  def create_conversion(for_account: account)
    for_account.conversions.create!(
      visitor: (for_account == account ? visitor : visitors(:two)),
      conversion_type: "Lead", converted_at: Time.current,
      idempotency_key: "ctrl_#{SecureRandom.hex(4)}"
    )
  end

  def delivered_dispatch
    @delivered_dispatch ||= ConversionDispatch.create!(
      conversion: create_conversion, conversion_destination: destination, account: account,
      status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago
    )
  end

  def failed_dispatch
    @failed_dispatch ||= ConversionDispatch.create!(
      conversion: create_conversion, conversion_destination: destination, account: account,
      status: ConversionDispatch::Statuses::FAILED_PERMANENT, error: "Invalid event_name"
    )
  end

  def other_destination_dispatch
    @other_destination_dispatch ||= ConversionDispatch.create!(
      conversion: create_conversion, conversion_destination: other_destination, account: account,
      status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago
    )
  end

  def other_account_dispatch
    @other_account_dispatch ||= ConversionDispatch.create!(
      conversion: create_conversion(for_account: other_account),
      conversion_destination: other_account_destination, account: other_account,
      status: ConversionDispatch::Statuses::DELIVERED, fired_at: 1.minute.ago
    )
  end
end
