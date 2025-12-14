# frozen_string_literal: true

require "test_helper"

class Admin::SubmissionsControllerTest < ActionDispatch::IntegrationTest
  # --- Index ---

  test "index requires admin user" do
    sign_in_as(admin_user)

    get admin_submissions_path

    assert_response :success
  end

  test "index redirects non-admin users" do
    sign_in_as(regular_user)

    get admin_submissions_path

    assert_redirected_to root_path
    assert_equal "Access denied.", flash[:alert]
  end

  test "index redirects unauthenticated users" do
    get admin_submissions_path

    assert_redirected_to login_path
  end

  test "index displays all submission types" do
    sign_in_as(admin_user)

    get admin_submissions_path

    assert_response :success
    assert_select "table"
  end

  test "index paginates results" do
    sign_in_as(admin_user)

    get admin_submissions_path

    assert_response :success
    # Should show submissions from fixtures
    assert_select "tr.submission-row"
  end

  test "index shows submission type badges" do
    sign_in_as(admin_user)

    get admin_submissions_path

    assert_select "[data-testid='type-badge']"
  end

  # --- Show ---

  test "show requires admin user" do
    sign_in_as(admin_user)

    get admin_submission_path(contact_submission)

    assert_response :success
  end

  test "show redirects non-admin users" do
    sign_in_as(regular_user)

    get admin_submission_path(contact_submission)

    assert_redirected_to root_path
  end

  test "show displays contact submission details" do
    sign_in_as(admin_user)

    get admin_submission_path(contact_submission)

    assert_response :success
    assert_select "h1", text: /Contact/
    assert_match contact_submission.email, response.body
    assert_match contact_submission.name, response.body
    assert_match contact_submission.message, response.body
  end

  test "show displays waitlist submission details" do
    sign_in_as(admin_user)

    get admin_submission_path(waitlist_submission)

    assert_response :success
    assert_match waitlist_submission.email, response.body
    assert_match waitlist_submission.role, response.body
    assert_match waitlist_submission.framework, response.body
  end

  test "show displays feature waitlist submission details" do
    sign_in_as(admin_user)

    get admin_submission_path(feature_waitlist_submission)

    assert_response :success
    assert_match feature_waitlist_submission.email, response.body
    assert_match feature_waitlist_submission.feature_name, response.body
    assert_match feature_waitlist_submission.feature_key, response.body
  end

  test "show displays metadata" do
    sign_in_as(admin_user)

    get admin_submission_path(contact_submission)

    assert_response :success
    assert_match contact_submission.ip_address, response.body
    assert_match contact_submission.user_agent, response.body
  end

  private

  def sign_in_as(user)
    post login_path, params: { email: user.email, password: "password123" }
  end

  def admin_user
    @admin_user ||= users(:admin)
  end

  def regular_user
    @regular_user ||= users(:one)
  end

  def contact_submission
    @contact_submission ||= form_submissions(:contact_general)
  end

  def waitlist_submission
    @waitlist_submission ||= form_submissions(:waitlist_one)
  end

  def feature_waitlist_submission
    @feature_waitlist_submission ||= form_submissions(:feature_waitlist_data_export)
  end
end
