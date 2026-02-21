# frozen_string_literal: true

require "test_helper"

class FeatureWaitlistControllerTest < ActionDispatch::IntegrationTest
  # --- Logged In Users ---

  test "create with logged-in user auto-fills email" do
    sign_in

    assert_difference("FeatureWaitlistSubmission.count", 1) do
      post feature_waitlist_path, params: valid_params
    end

    submission = FeatureWaitlistSubmission.last

    assert_equal user.email, submission.email
  end

  test "create with logged-in user saves feature data" do
    sign_in

    post feature_waitlist_path, params: valid_params

    submission = FeatureWaitlistSubmission.last

    assert_equal "data_export", submission.feature_key
    assert_equal "Data Export", submission.feature_name
    assert_equal "dashboard", submission.context
  end

  test "create with logged-in user redirects back with success flash" do
    sign_in

    post feature_waitlist_path,
      params: valid_params,
      headers: { "HTTP_REFERER" => dashboard_path }

    assert_redirected_to dashboard_path
    assert_match(/waitlist/, flash[:notice])
  end

  test "create with logged-in user captures IP and user agent" do
    sign_in

    post feature_waitlist_path,
      params: valid_params,
      headers: { "HTTP_USER_AGENT" => "Test Browser" }

    submission = FeatureWaitlistSubmission.last

    assert_not_nil submission.ip_address
    assert_equal "Test Browser", submission.user_agent
  end

  # --- Logged Out Users ---

  test "create with logged-out user uses provided email" do
    assert_difference("FeatureWaitlistSubmission.count", 1) do
      post feature_waitlist_path, params: valid_params_with_email
    end

    submission = FeatureWaitlistSubmission.last

    assert_equal "guest@example.com", submission.email
  end

  test "create with logged-out user saves feature data" do
    post feature_waitlist_path, params: valid_params_with_email

    submission = FeatureWaitlistSubmission.last

    assert_equal "csv_export", submission.feature_key
    assert_equal "CSV Export", submission.feature_name
  end

  test "create with logged-out user redirects back with success flash" do
    post feature_waitlist_path,
      params: valid_params_with_email,
      headers: { "HTTP_REFERER" => root_path }

    assert_redirected_to root_path
    assert_match(/waitlist/, flash[:notice])
  end

  test "create with logged-out user without email fails" do
    assert_no_difference("FeatureWaitlistSubmission.count") do
      post feature_waitlist_path, params: valid_params
    end

    assert_redirected_to root_path
    assert_match(/email|required/i, flash[:alert])
  end

  # --- Validation ---

  test "create with invalid feature_key fails" do
    sign_in

    assert_no_difference("FeatureWaitlistSubmission.count") do
      post feature_waitlist_path, params: invalid_feature_params
    end

    assert_match(/feature|invalid/i, flash[:alert])
  end

  test "create with missing feature_key fails" do
    sign_in

    assert_no_difference("FeatureWaitlistSubmission.count") do
      post feature_waitlist_path, params: missing_feature_params
    end

    assert_match(/feature|required/i, flash[:alert])
  end

  # --- Edge Cases ---

  test "create without referer redirects to root" do
    sign_in

    post feature_waitlist_path, params: valid_params

    assert_redirected_to root_path
  end

  test "create prevents duplicate submissions for same feature" do
    sign_in
    post feature_waitlist_path, params: valid_params

    # Second submission for same feature
    assert_no_difference("FeatureWaitlistSubmission.count") do
      post feature_waitlist_path, params: valid_params
    end

    assert_match(/already|waitlist/i, flash[:notice])
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def user
    @user ||= users(:one)
  end

  def valid_params
    {
      feature_key: "data_export",
      feature_name: "Data Export",
      context: "dashboard"
    }
  end

  def valid_params_with_email
    {
      feature_key: "csv_export",
      feature_name: "CSV Export",
      email: "guest@example.com"
    }
  end

  def invalid_feature_params
    {
      feature_key: "invalid_feature",
      feature_name: "Invalid Feature"
    }
  end

  def missing_feature_params
    {
      feature_name: "Missing Key"
    }
  end
end
