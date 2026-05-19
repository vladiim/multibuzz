# frozen_string_literal: true

require "test_helper"

class Admin::GuidedSetupsControllerTest < ActionDispatch::IntegrationTest
  # --- Auth ---

  test "non-admin users are redirected with access denied" do
    sign_in_as(regular_user)

    get admin_guided_setups_path

    assert_redirected_to root_path
  end

  test "unauthenticated users are redirected to login" do
    get admin_guided_setups_path

    assert_redirected_to login_path
  end

  # --- Index ---

  test "admin sees the index with engagement rows" do
    guided_setup
    sign_in_as(admin_user)

    get admin_guided_setups_path

    assert_response :success
    assert_select "[data-testid='guided-setup-row']", count: 1
  end

  test "index flags stalled engagements" do
    guided_setup.update_columns(status: GuidedSetup.statuses[:in_progress], updated_at: 20.days.ago)
    sign_in_as(admin_user)

    get admin_guided_setups_path

    assert_select "[data-testid='stalled-badge']", count: 1
  end

  # --- Show ---

  test "show renders the engagement" do
    sign_in_as(admin_user)

    get admin_guided_setup_path(guided_setup)

    assert_response :success
    assert_select "[data-testid='guided-setup-status']"
  end

  # --- Update ---

  test "update saves the specialist and notes" do
    sign_in_as(admin_user)

    patch admin_guided_setup_path(guided_setup),
      params: { guided_setup: { specialist_name: "Dana", notes: "Kickoff booked" } }

    guided_setup.reload

    assert_equal "Dana", guided_setup.specialist_name
    assert_equal "Kickoff booked", guided_setup.notes
  end

  # --- Record milestone ---

  test "record_milestone stamps the milestone" do
    sign_in_as(admin_user)

    post record_milestone_admin_guided_setup_path(guided_setup), params: { milestone: "kickoff_call" }

    assert_predicate guided_setup.reload.kickoff_call_at, :present?
  end

  test "record_milestone for the value check delivers the engagement" do
    sign_in_as(admin_user)

    post record_milestone_admin_guided_setup_path(guided_setup), params: { milestone: "value_check" }

    assert_predicate guided_setup.reload, :delivered?
  end

  test "record_milestone rejects an unknown milestone without error" do
    sign_in_as(admin_user)

    post record_milestone_admin_guided_setup_path(guided_setup), params: { milestone: "lunch" }

    assert_redirected_to admin_guided_setup_path(guided_setup)
    assert_equal "Unknown milestone.", flash[:alert]
  end

  test "record_milestone requires admin" do
    sign_in_as(regular_user)

    post record_milestone_admin_guided_setup_path(guided_setup), params: { milestone: "kickoff_call" }

    assert_redirected_to root_path
  end

  private

  def admin_user = @admin_user ||= users(:admin)
  def regular_user = @regular_user ||= users(:one)

  def guided_setup
    @guided_setup ||= GuidedSetup.create!(account: accounts(:one))
  end
end
