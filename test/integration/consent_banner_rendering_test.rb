# frozen_string_literal: true

require "test_helper"
require "minitest/mock"

# Verifies the consent banner renders only for visitors in EEA/UK/CH/CA
# and is suppressed everywhere else. The Stimulus controller mount point
# is always present (so it can record auto-grant logs for non-banner geos),
# but the visible banner element is gated on geo.
class ConsentBannerRenderingTest < ActionDispatch::IntegrationTest
  GTM_TEST_CONTAINER_ID = "GTM-TESTING1"
  CONTROLLER_MOUNT = 'data-controller="consent-banner"'
  BANNER_TARGET = 'data-consent-banner-target="banner"'
  AUTO_GRANT_TRUE = 'data-consent-banner-auto-grant-value="true"'
  AUTO_GRANT_FALSE = 'data-consent-banner-auto-grant-value="false"'

  test "mounts the controller and renders the banner UI for EEA visitors" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "FR" }

      assert_includes response.body, CONTROLLER_MOUNT
      assert_includes response.body, BANNER_TARGET
      assert_includes response.body, AUTO_GRANT_FALSE
    end
  end

  test "mounts the controller for California visitors" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "US", "CF-Region-Code" => "CA" }

      assert_includes response.body, BANNER_TARGET
    end
  end

  test "mounts the controller in auto-grant mode for non-EEA visitors" do
    with_gtm_container do
      get root_path, headers: { "CF-IPCountry" => "AU" }

      assert_includes response.body, CONTROLLER_MOUNT
      assert_includes response.body, AUTO_GRANT_TRUE
      refute_includes response.body, BANNER_TARGET
    end
  end

  test "does not mount the controller on sensitive admin routes" do
    with_gtm_container do
      sign_in_admin
      get "/admin/accounts"

      refute_includes response.body, CONTROLLER_MOUNT
    end
  end

  test "does not mount the controller when no container id is configured" do
    get root_path, headers: { "CF-IPCountry" => "FR" }

    refute_includes response.body, CONTROLLER_MOUNT
  end

  test "cookies page exposes the manage preferences button" do
    get cookies_path

    assert_includes response.body, "click->consent-banner#openModal"
  end

  private

  def with_gtm_container
    fake_credentials = Object.new
    fake_credentials.define_singleton_method(:dig) { |*| GTM_TEST_CONTAINER_ID }
    Rails.application.stub(:credentials, fake_credentials) { yield }
  end

  def sign_in_admin
    user = users(:one)
    user.update!(is_admin: true)
    post login_path, params: { email: user.email, password: "password123" }
  end
end
