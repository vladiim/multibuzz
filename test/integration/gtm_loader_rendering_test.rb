# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Verifies the gtm-loader Stimulus mount renders on every page that opts
# in, and renders nothing on pages that opt out via skip_marketing_analytics
# or that match SensitivePaths. The mount is the load-bearing surface — if
# this test passes, GTM is correctly gated.
class GtmLoaderRenderingTest < ActionDispatch::IntegrationTest
  GTM_TEST_CONTAINER_ID = "GTM-TESTING1"
  LOADER_MOUNT_ATTRIBUTE = 'data-controller="gtm-loader"'
  CONSENT_DENIED_ATTRIBUTE = 'data-gtm-loader-consent-default-value="denied"'
  CONSENT_GRANTED_ATTRIBUTE = 'data-gtm-loader-consent-default-value="granted"'

  test "renders gtm-loader on the marketing root with denied consent for EEA visitors" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "FR" }

      assert_includes response.body, LOADER_MOUNT_ATTRIBUTE
      assert_includes response.body, CONSENT_DENIED_ATTRIBUTE
    end
  end

  test "renders gtm-loader on the marketing root with granted consent for non-EEA visitors" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "AU" }

      assert_includes response.body, LOADER_MOUNT_ATTRIBUTE
      assert_includes response.body, CONSENT_GRANTED_ATTRIBUTE
    end
  end

  test "does not render gtm-loader when no container id is configured" do
    get root_path, headers: { "CF-IPCountry" => "AU" }

    refute_includes response.body, LOADER_MOUNT_ATTRIBUTE
  end

  test "does not render gtm-loader on admin routes" do
    with_gtm_container do
      sign_in_admin
      get "/admin/accounts"

      refute_includes response.body, LOADER_MOUNT_ATTRIBUTE
    end
  end

  test "does not render gtm-loader on onboarding install" do
    with_gtm_container do
      sign_in
      get "/onboarding/install"

      refute_includes response.body, LOADER_MOUNT_ATTRIBUTE
    end
  end

  test "does not render gtm-loader on api keys route" do
    with_gtm_container do
      sign_in
      get "/accounts/#{account.prefix_id}/api_keys"

      refute_includes response.body, LOADER_MOUNT_ATTRIBUTE
    end
  end

  test "does not render gtm-loader on billing route" do
    with_gtm_container do
      sign_in
      get "/accounts/#{account.prefix_id}/billing"

      refute_includes response.body, LOADER_MOUNT_ATTRIBUTE
    end
  end

  test "container id is rendered into the data attribute" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "AU" }

      assert_includes response.body, %(data-gtm-loader-container-id-value="#{GTM_TEST_CONTAINER_ID}")
    end
  end

  private

  def with_gtm_container
    fake_credentials = Object.new
    fake_credentials.define_singleton_method(:dig) { |*| GTM_TEST_CONTAINER_ID }
    Rails.application.stub(:credentials, fake_credentials) { yield }
  end

  def sign_in
    post login_path, params: { email: user.email, password: "password123" }
  end

  def sign_in_admin
    user.update!(is_admin: true)
    sign_in
  end

  def user
    @user ||= users(:one)
  end

  def account
    @account ||= accounts(:one)
  end
end
