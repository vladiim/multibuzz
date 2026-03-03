# frozen_string_literal: true

require "test_helper"

class Accounts::IntegrationsControllerTest < ActionDispatch::IntegrationTest
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

  test "show displays connected status for existing connection" do
    sign_in

    get account_integrations_path

    assert_select "span", /Connected/i
  end

  test "show displays connect button when no connection exists" do
    sign_in
    connection.mark_disconnected!

    get account_integrations_path

    assert_select "a", text: /Connect/i
  end

  test "show displays last synced time for connected account" do
    sign_in

    get account_integrations_path

    assert_match(/Last synced/, response.body)
  end

  test "show displays upgrade CTA when cannot connect" do
    sign_in
    account.ad_platform_connections.each(&:mark_disconnected!)
    account.update!(plan: nil)

    get account_integrations_path

    assert_select "a", text: /Upgrade/i
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

  # --- multi-tenancy ---

  test "does not show other account connections" do
    sign_in

    get account_integrations_path

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
end
