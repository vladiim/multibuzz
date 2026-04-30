# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Oauth::MetaAdsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper

  # --- connect ---

  test "connect requires authentication" do
    get oauth_meta_ads_connect_path

    assert_redirected_to login_path
  end

  test "connect redirects when feature flag is off" do
    sign_in
    assign_plan(:growth)

    get oauth_meta_ads_connect_path

    assert_redirected_to account_integrations_path
    assert_match(/not enabled/i, flash[:alert])
  end

  test "connect redirects with paid-plan error when flag on but free plan" do
    enable_meta_flag
    sign_in

    get oauth_meta_ads_connect_path

    assert_redirected_to account_integrations_path
    assert_match(/paid plan/i, flash[:alert])
  end

  test "connect redirects with at-limit error when starter is full" do
    enable_meta_flag
    sign_in
    assign_plan(:starter)

    get oauth_meta_ads_connect_path

    assert_redirected_to account_integrations_path
    assert_match(/2 of 2/i, flash[:alert])
  end

  test "connect redirects to Meta OAuth dialog when flag on and slot available" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)

    AdPlatforms::Meta.stub(:credentials, test_credentials) do
      get oauth_meta_ads_connect_path
    end

    assert_response :redirect
    assert_match(%r{facebook\.com/v\d+\.\d+/dialog/oauth\?.+scope=ads_read.+state=\w+}, response.location)
  end

  # --- callback ---

  test "callback rejects request with mismatched state" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)
    state = simulate_connect

    get oauth_meta_ads_callback_path, params: { state: "tampered_#{state}", code: "auth_code" }

    assert_redirected_to account_integrations_path
    assert_match(/verification failed/i, flash[:alert])
  end

  test "callback rejects when state param is missing" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)
    simulate_connect

    get oauth_meta_ads_callback_path, params: { code: "auth_code" }

    assert_redirected_to account_integrations_path
    assert_match(/verification failed/i, flash[:alert])
  end

  # --- select_account ---

  test "select_account redirects to integrations when no oauth account is pinned" do
    enable_meta_flag
    sign_in

    get oauth_meta_ads_select_account_path

    assert_redirected_to account_integrations_path
  end

  # --- create_connection ---

  test "create_connection redirects to integrations when session tokens are missing" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)

    post oauth_meta_ads_create_connection_path, params: { ad_account_id: "act_1234567890" }

    assert_redirected_to account_integrations_path
  end

  # --- done ---

  test "done redirects to the Meta Ads page" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)
    simulate_connect

    post oauth_meta_ads_done_path

    assert_redirected_to meta_ads_account_integrations_path
  end

  test "done clears all oauth session keys" do
    enable_meta_flag
    sign_in
    assign_plan(:pro)
    simulate_connect

    post oauth_meta_ads_done_path

    assert_equal({}, session.to_h.slice("oauth_account_id", "meta_ads_tokens", "oauth_state"))
  end

  # --- disconnect ---

  test "disconnect marks the connection as disconnected" do
    sign_in
    meta = build_meta_connection

    delete oauth_meta_ads_disconnect_path(meta)

    assert_redirected_to account_integrations_path
    assert_predicate meta.reload, :disconnected?
  end

  test "disconnect cannot touch another account's connection" do
    meta = build_meta_connection
    sign_in_as_user_two

    delete oauth_meta_ads_disconnect_path(meta)

    assert_response :not_found
    assert_predicate meta.reload, :connected?
  end

  # --- reconnect ---

  test "reconnect requires authentication" do
    meta = build_meta_connection

    get oauth_meta_ads_reconnect_path(meta)

    assert_redirected_to login_path
  end

  test "reconnect redirects when feature flag is off" do
    sign_in
    meta = build_meta_connection

    get oauth_meta_ads_reconnect_path(meta)

    assert_redirected_to account_integrations_path
    assert_match(/not enabled/i, flash[:alert])
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def sign_in_as_user_two
    post login_path, params: { email: users(:two).email, password: "password123" }
  end

  def enable_meta_flag
    account.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)
    # User :one is also a member of account :two. After the first authenticated request
    # touches account :one's last_accessed_at, primary_account drifts to :two (Postgres
    # NULLS-first DESC ordering). Enabling the flag on both accounts keeps the gate
    # check stable across requests.
    other_account.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)
  end

  def assign_plan(plan_name)
    account.update!(plan: plans(plan_name))
  end

  def simulate_connect
    AdPlatforms::Meta.stub(:credentials, test_credentials) do
      get oauth_meta_ads_connect_path
    end
    URI.decode_www_form(URI.parse(response.location).query).to_h["state"]
  end

  def build_meta_connection
    account.ad_platform_connections.create!(
      platform: :meta_ads,
      platform_account_id: "act_1111111111",
      platform_account_name: "Acme Meta Ads",
      currency: "USD",
      access_token: "meta_test_token",
      refresh_token: "meta_test_token",
      token_expires_at: 60.days.from_now,
      status: :connected
    )
  end

  def test_credentials
    { app_id: "test_app_id", app_secret: "test_app_secret" }
  end

  def user = @user ||= users(:one)
  def account = @account ||= accounts(:one)
  def other_account = @other_account ||= accounts(:two)
end
