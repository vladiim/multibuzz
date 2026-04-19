# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

class Oauth::GoogleAdsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
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

  test "connect redirects with error when no paid plan" do
    sign_in

    get oauth_google_ads_connect_path

    assert_redirected_to account_integrations_path
    assert_match(/paid plan/i, flash[:alert])
  end

  test "connect redirects with at-limit error when starter is full" do
    sign_in
    assign_plan(:starter)
    # account :one fixture already has 2 connections; starter limit is 2

    get oauth_google_ads_connect_path

    assert_redirected_to account_integrations_path
    assert_match(/2 of 2/i, flash[:alert])
    assert_match(/upgrade/i, flash[:alert])
  end

  test "connect initiates oauth when starter has room" do
    sign_in
    assign_plan(:starter)
    connection.mark_disconnected!
    # 1 active connection remains; starter limit is 2

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end

    assert_response :redirect
    assert_includes response.location, "accounts.google.com"
  end

  test "connect initiates oauth for pro plan regardless of connection count" do
    sign_in
    assign_plan(:pro)
    # bulk-create many connections to simulate a busy Pro account
    10.times do |i|
      account.ad_platform_connections.create!(
        platform: :google_ads,
        platform_account_id: "pro-bulk-#{i}",
        platform_account_name: "Pro Bulk #{i}",
        currency: "USD",
        access_token: "tok",
        refresh_token: "ref",
        token_expires_at: 1.hour.from_now,
        status: :connected
      )
    end

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_connect_path
    end

    assert_response :redirect
    assert_includes response.location, "accounts.google.com"
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

    assert_redirected_to account_integrations_path
    assert_match(/verification failed/i, flash[:alert])
  end

  test "callback rejects missing state parameter" do
    sign_in
    assign_plan(:growth)

    get oauth_google_ads_callback_path, params: { code: "auth_code" }

    assert_redirected_to account_integrations_path
    assert_match(/OAuth session expired/i, flash[:alert])
  end

  test "callback handles token exchange failure" do
    sign_in
    assign_plan(:growth)

    state = simulate_connect

    stub_exchanger(success: false, errors: [ "Google OAuth error: invalid_grant" ]) do
      get oauth_google_ads_callback_path, params: { state: state, code: "bad_code" }
    end

    assert_redirected_to account_integrations_path
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

    assert_redirected_to account_integrations_path
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

    assert_redirected_to account_integrations_path
  end

  test "create_connection redirects when account hit limit mid-flow" do
    sign_in
    assign_plan(:growth)
    set_session_tokens
    # mid-flow: downgrade to starter, which already has the 2 fixture connections at its limit
    assign_plan(:starter)

    assert_no_difference "AdPlatformConnection.count" do
      post oauth_google_ads_create_connection_path, params: {
        customer_id: "race-1111111", customer_name: "Race", currency: "USD"
      }
    end

    assert_redirected_to account_integrations_path
    assert_match(/2 of 2/i, flash[:alert])
  end

  test "create_connection clears oauth session when blocked by at-limit" do
    sign_in
    assign_plan(:growth)
    set_session_tokens
    assign_plan(:starter)

    post oauth_google_ads_create_connection_path, params: {
      customer_id: "race-2222222", customer_name: "Race", currency: "USD"
    }

    assert_nil session[:oauth_account_id]
    assert_nil session[:google_ads_tokens]
  end

  test "create_connection rejects duplicate platform account" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    post oauth_google_ads_create_connection_path, params: {
      customer_id: connection.platform_account_id, customer_name: "Dupe", currency: "USD"
    }

    assert_redirected_to account_integrations_path
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

  test "create_connection enqueues backfill sync job" do
    sign_in
    assign_plan(:growth)
    set_session_tokens

    assert_enqueued_with(job: AdPlatforms::SpendSyncJob) do
      post oauth_google_ads_create_connection_path, params: {
        customer_id: "8889990000", customer_name: "Backfill Test", currency: "USD"
      }
    end
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

  # --- reconnect (re-auth) ---

  test "reconnect redirects to Google OAuth" do
    sign_in
    connection.mark_needs_reauth!

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_reconnect_path(connection)
    end

    assert_response :redirect
    assert_includes response.location, "accounts.google.com"
  end

  test "reconnect pins connection id in session" do
    sign_in
    connection.mark_needs_reauth!

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_reconnect_path(connection)
    end

    assert_equal connection.prefix_id, session[:oauth_reconnect_id]
  end

  test "reconnect callback updates existing connection tokens" do
    sign_in
    connection.mark_needs_reauth!

    # Simulate full reconnect flow: reconnect → callback
    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_reconnect_path(connection)
    end
    state = URI.decode_www_form(URI.parse(response.location).query).to_h["state"]

    stub_exchanger(success_tokens) do
      get oauth_google_ads_callback_path, params: { state: state, code: "reauth_code" }
    end

    connection.reload

    assert_equal "access_123", connection.access_token
    assert_equal "refresh_456", connection.refresh_token
    assert_predicate connection, :connected?
  end

  test "reconnect callback does not create a new connection" do
    sign_in
    connection.mark_needs_reauth!

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_reconnect_path(connection)
    end
    state = URI.decode_www_form(URI.parse(response.location).query).to_h["state"]

    assert_no_difference "AdPlatformConnection.count" do
      stub_exchanger(success_tokens) do
        get oauth_google_ads_callback_path, params: { state: state, code: "reauth_code" }
      end
    end
  end

  test "reconnect cannot access other account connections" do
    sign_in

    AdPlatforms::Google.stub(:credentials, test_credentials) do
      get oauth_google_ads_reconnect_path(other_connection)
    end

    assert_response :not_found
  end

  # --- disconnect ---

  test "disconnect marks connection as disconnected" do
    sign_in

    delete oauth_google_ads_disconnect_path(connection)

    assert_predicate connection.reload, :disconnected?
    assert_redirected_to account_integrations_path
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
