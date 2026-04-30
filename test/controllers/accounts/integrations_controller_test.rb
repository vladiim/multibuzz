# frozen_string_literal: true

require "test_helper"

class Accounts::IntegrationsControllerTest < ActionDispatch::IntegrationTest
  include ActiveJob::TestHelper
  # --- show ---

  test "show renders integrations page" do
    sign_in

    get account_integrations_path

    assert_response :success
    assert_select "h1", text: /Integrations/i
  end

  test "show displays Google Ads connection card" do
    sign_in

    get account_integrations_path

    assert_select "[data-platform='google-ads']"
  end

  test "show displays connected status for platform card" do
    sign_in

    get account_integrations_path

    assert_select "span", /Connected/i
  end

  test "show links to Google Ads platform page" do
    sign_in

    get account_integrations_path

    assert_select "a[href='#{google_ads_account_integrations_path}']"
  end

  test "show displays account count for connected platform" do
    sign_in

    get account_integrations_path

    assert_match(/account.* connected/i, response.body)
  end

  test "show displays usage badge for paid accounts with a limit" do
    sign_in
    account.update!(plan: plans(:starter))

    get account_integrations_path

    assert_match(/2 of 2 integrations used/i, response.body)
  end

  test "show displays Unlimited badge for pro accounts" do
    sign_in
    account.update!(plan: plans(:pro))

    get account_integrations_path

    assert_match(/Unlimited integrations/i, response.body)
  end

  test "show hides usage badge for unpaid accounts" do
    sign_in
    account.update!(plan: plans(:free))

    get account_integrations_path

    assert_no_match(/integrations used/i, response.body)
    assert_no_match(/Unlimited integrations/i, response.body)
  end

  # --- google_ads (platform page) ---

  test "google_ads renders platform page with breadcrumb" do
    sign_in

    get google_ads_account_integrations_path

    assert_response :success
    assert_match(/Integrations/, response.body)
    assert_match(/Google Ads/, response.body)
  end

  test "google_ads lists connected accounts" do
    sign_in

    get google_ads_account_integrations_path

    assert_select "[data-connection-id='#{connection.prefix_id}']"
  end

  test "google_ads shows connect button for paid accounts" do
    sign_in
    account.update!(plan: plans(:growth))

    get google_ads_account_integrations_path

    assert_select "a", text: /Connect Account/
  end

  test "google_ads opens at-limit modal when starter is full" do
    sign_in
    account.update!(plan: plans(:starter))
    # fixture already has 2 connections; starter limit is 2

    get google_ads_account_integrations_path

    assert_select "button[data-modal-target-value='at-limit-modal']", text: /Connect Account/
    assert_match(/2 of 2/i, response.body)
  end

  test "google_ads opens subscription-required modal for free accounts" do
    sign_in
    account.update!(plan: plans(:free))

    get google_ads_account_integrations_path

    assert_select "button[data-modal-target-value='subscription-required-modal']", text: /Connect Account/
  end

  # --- google_ads_account (account detail page) ---

  test "google_ads_account renders account detail with breadcrumb" do
    sign_in

    get google_ads_detail_account_integrations_path(connection)

    assert_response :success
    assert_match connection.platform_account_name, response.body
  end

  test "google_ads_account shows sync history" do
    sign_in
    connection.ad_spend_sync_runs.create!(
      sync_date: Date.current, status: :completed,
      records_synced: 100, started_at: 1.minute.ago, completed_at: Time.current
    )

    get google_ads_detail_account_integrations_path(connection)

    assert_match(/100/, response.body)
  end

  test "google_ads_account shows re-authenticate for needs_reauth" do
    sign_in
    connection.mark_needs_reauth!

    get google_ads_detail_account_integrations_path(connection)

    assert_select "a[href*='reconnect']"
  end

  test "google_ads_account cannot access other account connections" do
    sign_in

    get google_ads_detail_account_integrations_path(other_connection)

    assert_response :not_found
  end

  # --- auth ---

  test "requires authentication" do
    get account_integrations_path

    assert_redirected_to login_path
  end

  test "requires admin access" do
    sign_in_as_member

    get account_integrations_path

    assert_response :forbidden
  end

  # --- refresh ---

  test "refresh enqueues sync job for connection" do
    sign_in

    assert_enqueued_with(job: AdPlatforms::SpendSyncJob) do
      post refresh_account_integrations_path(connection)
    end

    assert_redirected_to account_integrations_path
  end

  test "refresh cannot sync other account connections" do
    sign_in

    post refresh_account_integrations_path(other_connection)

    assert_response :not_found
  end

  test "refresh requires authentication" do
    post refresh_account_integrations_path(connection)

    assert_redirected_to login_path
  end

  # --- notify ---

  test "notify creates integration request submission" do
    sign_in

    assert_difference "IntegrationRequestSubmission.count", 1 do
      post notify_account_integrations_path, params: { platform_name: "Meta Ads" }
    end

    assert_redirected_to account_integrations_path
    assert_match(/notify you/, flash[:notice])
  end

  test "notify prevents duplicate for same platform" do
    sign_in
    IntegrationRequestSubmission.create!(email: user.email, platform_name: "Meta Ads")

    assert_no_difference "IntegrationRequestSubmission.count" do
      post notify_account_integrations_path, params: { platform_name: "Meta Ads" }
    end

    assert_match(/already requested/, flash[:notice])
  end

  test "show displays coming soon cards with Notify Me buttons" do
    sign_in

    get account_integrations_path

    assert_select "[data-platform='meta-ads']"
    assert_select "[data-platform='linkedin-ads']"
    assert_select "[data-platform='microsoft-ads-bing']"
  end

  test "show displays Notified badge for already-requested platforms" do
    sign_in
    IntegrationRequestSubmission.create!(email: user.email, platform_name: "Meta Ads")

    get account_integrations_path

    assert_select "[data-platform='meta-ads']" do
      assert_select "span", /Notified/
    end
  end

  # --- request_integration ---

  test "request_integration creates submission with full params" do
    sign_in

    assert_difference "IntegrationRequestSubmission.count", 1 do
      post request_integration_account_integrations_path, params: {
        platform_name: "Other",
        platform_name_other: "Spotify Ads",
        monthly_spend: "$1K – $10K",
        notes: "Need this soon"
      }
    end

    assert_redirected_to account_integrations_path
  end

  test "notify requires authentication" do
    post notify_account_integrations_path, params: { platform_name: "Meta Ads" }

    assert_redirected_to login_path
  end

  # --- meta_ads (feature-flagged) ---

  test "show renders Meta Ads as Coming Soon when feature flag off" do
    sign_in

    get account_integrations_path

    assert_select "a[href='#{meta_ads_account_integrations_path}']", count: 0
    assert_match(/Meta Ads/, response.body)
    assert_match(/Coming soon/, response.body)
  end

  test "show renders live Meta Ads card when feature flag on" do
    account.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)
    sign_in

    get account_integrations_path

    assert_select "[data-platform='meta-ads']"
    assert_select "a[href='#{meta_ads_account_integrations_path}']"
  end

  test "meta_ads redirects when feature flag is off" do
    sign_in

    get meta_ads_account_integrations_path

    assert_redirected_to account_integrations_path
    assert_match(/not enabled/i, flash[:alert])
  end

  test "meta_ads renders index when feature flag is on" do
    account.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)
    meta = build_meta_connection
    sign_in

    get meta_ads_account_integrations_path

    assert_response :success
    assert_select "h1", text: /Meta Ads/
    assert_match(meta.platform_account_name, response.body)
  end

  test "meta_ads_account renders detail when feature flag is on" do
    account.enable_feature!(FeatureFlags::META_ADS_INTEGRATION)
    meta = build_meta_connection
    sign_in

    get meta_ads_detail_account_integrations_path(meta)

    assert_response :success
    assert_match(meta.platform_account_name, response.body)
  end

  test "meta_ads_account redirects when feature flag is off" do
    meta = build_meta_connection
    sign_in

    get meta_ads_detail_account_integrations_path(meta)

    assert_redirected_to account_integrations_path
  end

  # --- multi-tenancy ---

  test "google_ads does not show other account connections" do
    sign_in

    get google_ads_account_integrations_path

    assert_select "[data-connection-id='#{other_connection.prefix_id}']", count: 0
  end

  private

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def sign_in_as_member
    post login_path, params: { email: member.email, password: "password123" }
  end

  def user = @user ||= users(:one)
  def member = @member ||= users(:four)
  def account = @account ||= accounts(:one)
  def connection = @connection ||= ad_platform_connections(:google_ads)
  def other_connection = @other_connection ||= ad_platform_connections(:other_account_google)

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
end
