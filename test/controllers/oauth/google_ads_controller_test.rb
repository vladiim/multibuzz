# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Oauth::GoogleAdsControllerTest < ActionDispatch::IntegrationTest
  # --- connect ---

  test "connect redirects to Google OAuth consent screen" do
    sign_in
    assign_plan(:growth)

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end

    assert_response :redirect
    assert_includes response.location, "accounts.google.com"
  end

  test "connect includes state parameter in redirect URL" do
    sign_in
    assign_plan(:growth)

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end

    assert_includes response.location, "state="
  end

  test "connect requires authentication" do
    get oauth_google_ads_connect_path

    assert_redirected_to login_path
  end

  test "connect redirects with error when connection limit reached" do
    sign_in

    get oauth_google_ads_connect_path

    assert_redirected_to account_path
    assert_match(/limit/i, flash[:alert])
  end

  # --- callback ---

  test "callback exchanges code and stores tokens in session" do
    sign_in
    assign_plan(:growth)

    state = simulate_connect

    stub_exchanger(success_tokens) do
      get oauth_google_ads_callback_path, params: { state: state, code: "auth_code" }
    end

    assert_response :redirect
    assert_not_includes flash[:alert].to_s, "error"
  end

  test "callback rejects mismatched state parameter" do
    sign_in
    assign_plan(:growth)
    simulate_connect

    get oauth_google_ads_callback_path, params: { state: "wrong_state", code: "auth_code" }

    assert_redirected_to account_path
    assert_match(/verification failed/i, flash[:alert])
  end

  test "callback rejects missing state parameter" do
    sign_in
    assign_plan(:growth)

    get oauth_google_ads_callback_path, params: { code: "auth_code" }

    assert_redirected_to account_path
    assert_match(/OAuth session expired/i, flash[:alert])
  end

  test "callback handles token exchange failure" do
    sign_in
    assign_plan(:growth)

    state = simulate_connect

    stub_exchanger(success: false, errors: [ "Google OAuth error: invalid_grant" ]) do
      get oauth_google_ads_callback_path, params: { state: state, code: "bad_code" }
    end

    assert_redirected_to account_path
    assert_match(/invalid_grant/i, flash[:alert])
  end

  test "callback requires authentication" do
    get oauth_google_ads_callback_path, params: { state: "x", code: "y" }

    assert_redirected_to login_path
  end

  # --- select_account ---

  test "select_account lists accessible customers" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    stub_list_customers(customer_list) do
      get oauth_google_ads_select_account_path
    end

    assert_response :success
    assert_select "input[value='1234567890']"
  end

  test "select_account redirects without oauth session" do
    sign_in
    assign_plan(:growth)

    get oauth_google_ads_select_account_path

    assert_redirected_to account_path
    assert_match(/OAuth session expired/i, flash[:alert])
  end

  # --- create_connection ---

  test "create_connection creates ad platform connection" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    assert_difference "AdPlatformConnection.count", 1 do
      post oauth_google_ads_create_connection_path, params: {
        customer_id: "5551234567", customer_name: "New Ads", currency: "AUD"
      }
    end

    conn = AdPlatformConnection.last

    assert_equal "5551234567", conn.platform_account_id
    assert_predicate conn, :connected?
  end

  test "create_connection stores encrypted tokens from session" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "5551234567", customer_name: "New Ads", currency: "AUD"
    }

    conn = AdPlatformConnection.last

    assert_equal "access_123", conn.access_token
    assert_equal "refresh_456", conn.refresh_token
  end

  test "create_connection redirects without session tokens" do
    sign_in
    assign_plan(:growth)

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "123", customer_name: "X", currency: "USD"
    }

    assert_redirected_to account_path
  end

  test "create_connection rejects duplicate platform account" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    post oauth_google_ads_create_connection_path, params: {
      customer_id: connection.platform_account_id, customer_name: "Dupe", currency: "USD"
    }

    assert_redirected_to account_path
    assert_match(/already connected/i, flash[:alert])
    assert_no_difference "AdPlatformConnection.count" do
      post oauth_google_ads_create_connection_path, params: {
        customer_id: connection.platform_account_id, customer_name: "Dupe", currency: "USD"
      }
    end
  end

  # --- session pinning (multi-account safety) ---

  test "connect stores oauth_account_id in session" do
    sign_in
    assign_plan(:growth)

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end

    assert_equal account.id, session[:oauth_account_id]
  end

  test "create_connection uses pinned account even when primary_account changes" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    # Simulate primary_account switching: touch other account's membership
    # so primary_account would resolve to the wrong account
    account_memberships(:member_one_in_two).update!(last_accessed_at: 1.second.from_now)

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "9999999999", customer_name: "Pinned Test", currency: "USD"
    }

    conn = AdPlatformConnection.last

    assert_equal account.id, conn.account_id
    assert_equal "9999999999", conn.platform_account_id
  end

  test "create_connection clears oauth_account_id from session" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "5551234567", customer_name: "Cleanup Test", currency: "AUD"
    }

    assert_nil session[:oauth_account_id]
  end

  test "create_connection clears all oauth session keys" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "7778889999", customer_name: "Full Cleanup", currency: "USD"
    }

    assert_nil session[:oauth_account_id]
    assert_nil session[:google_ads_tokens]
    assert_nil session[:oauth_state]
  end

  # --- disconnect ---

  test "disconnect marks connection as disconnected" do
    sign_in

    delete oauth_google_ads_disconnect_path(connection)

    assert_predicate connection.reload, :disconnected?
    assert_redirected_to account_path
  end

  test "disconnect clears tokens" do
    sign_in

    delete oauth_google_ads_disconnect_path(connection)

    connection.reload

    assert_nil connection.access_token
    assert_nil connection.refresh_token
  end

  test "disconnect requires authentication" do
    delete oauth_google_ads_disconnect_path(connection)

    assert_redirected_to login_path
  end

  test "disconnect cannot access other account connections" do
    sign_in

    delete oauth_google_ads_disconnect_path(other_connection)

    assert_response :not_found
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def simulate_connect
    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end
    URI.decode_www_form(URI.parse(response.location).query).to_h["state"]
  end

  def stub_exchanger(response)
    mock = ->(_) { OpenStruct.new(call: response) }

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      AdPlatforms::Google::TokenExchanger.stub(:new, mock) do
        yield
      end
    end
  end

  def assign_plan(plan_name)
    account.update!(plan: plans(plan_name))
  end

  def success_tokens
    {
      success: true,
      access_token: "access_123",
      refresh_token: "refresh_456",
      expires_at: 1.hour.from_now
    }
  end

  def set_session_tokens
    mock = ->(_) { OpenStruct.new(call: success_tokens) }

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
      state = URI.decode_www_form(URI.parse(response.location).query).to_h["state"]

      AdPlatforms::Google::TokenExchanger.stub(:new, mock) do
        get oauth_google_ads_callback_path, params: { state: state, code: "auth_code" }
      end
    end
  end

  def stub_list_customers(response)
    mock = ->(_) { OpenStruct.new(call: response) }

    AdPlatforms::Google::ListCustomers.stub(:new, mock) do
      yield
    end
  end

  def customer_list
    {
      success: true,
      customers: [ { id: "1234567890", name: "Acme Ads", currency: "USD" } ]
    }
  end

  def test_credentials
    { client_id: "test_client_id", client_secret: "test_client_secret", developer_token: "test_dev_token" }
  end

  def user = @user ||= users(:one)
  def account = @account ||= accounts(:one)
  def connection = @connection ||= ad_platform_connections(:google_ads)
  def other_connection = @other_connection ||= ad_platform_connections(:other_account_google)
end
