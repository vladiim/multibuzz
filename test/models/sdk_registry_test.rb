require "test_helper"

class SdkRegistryTest < ActiveSupport::TestCase
  test ".all returns all SDKs sorted by sort_order" do
    sdks = SdkRegistry.all

    assert sdks.any?
    assert_equal sdks.map(&:sort_order), sdks.map(&:sort_order).sort
  end

  test ".find returns SDK by key" do
    sdk = SdkRegistry.find(:ruby)

    assert_equal "ruby", sdk.key
    assert_equal "Ruby", sdk.name
    assert_equal "Ruby / Rails", sdk.display_name
  end

  test ".find returns nil for unknown key" do
    assert_nil SdkRegistry.find(:unknown)
  end

  test ".live returns only live SDKs" do
    sdks = SdkRegistry.live

    assert sdks.any?
    assert sdks.all?(&:live?)
  end

  test ".coming_soon returns only coming_soon SDKs" do
    sdks = SdkRegistry.coming_soon

    assert sdks.any?
    assert sdks.all?(&:coming_soon?)
  end

  test ".server_side returns only server_side SDKs" do
    sdks = SdkRegistry.server_side

    assert sdks.any?
    assert sdks.all?(&:server_side?)
  end

  test ".platform returns only platform SDKs" do
    sdks = SdkRegistry.platform

    assert sdks.any?
    assert sdks.all?(&:platform?)
  end

  test ".api returns only api SDKs" do
    sdks = SdkRegistry.api

    assert sdks.any?
    assert sdks.all?(&:api?)
  end

  test ".for_onboarding returns live server-side and API SDKs plus coming_soon server-side" do
    sdks = SdkRegistry.for_onboarding

    assert sdks.any?

    live_sdks = sdks.select(&:live?)
    coming_soon_sdks = sdks.select(&:coming_soon?)

    # Live SDKs should be server_side or api
    assert live_sdks.all? { |sdk| sdk.server_side? || sdk.api? }

    # Coming soon SDKs should be server_side only
    assert coming_soon_sdks.all?(&:server_side?)
  end

  # Sdk struct tests
  test "Sdk#live? returns true for live status" do
    sdk = SdkRegistry.find(:ruby)

    assert sdk.live?
    assert_not sdk.coming_soon?
    assert_not sdk.beta?
  end

  test "Sdk#coming_soon? returns true for coming_soon status" do
    sdk = SdkRegistry.find(:python)

    assert sdk.coming_soon?
    assert_not sdk.live?
  end

  test "Sdk#server_side? returns true for server_side category" do
    sdk = SdkRegistry.find(:ruby)

    assert sdk.server_side?
    assert_not sdk.platform?
    assert_not sdk.api?
  end

  test "Sdk#platform? returns true for platform category" do
    sdk = SdkRegistry.find(:shopify)

    assert sdk.platform?
    assert_not sdk.server_side?
  end

  test "Sdk#api? returns true for api category" do
    sdk = SdkRegistry.find(:rest_api)

    assert sdk.api?
    assert_not sdk.server_side?
  end

  test "Sdk#status_badge returns human-readable badge" do
    live_sdk = SdkRegistry.find(:ruby)
    coming_soon_sdk = SdkRegistry.find(:python)

    assert_equal "Live", live_sdk.status_badge
    assert_equal "Coming Soon", coming_soon_sdk.status_badge
  end

  # Code snippets tests
  test "SDK contains code snippets for server-side SDKs" do
    sdk = SdkRegistry.find(:ruby)

    assert sdk.init_code.present?
    assert sdk.event_code.present?
    assert sdk.conversion_code.present?
    assert sdk.identify_code.present?
  end

  test "REST API contains curl examples" do
    sdk = SdkRegistry.find(:rest_api)

    assert sdk.init_code.present?
    assert sdk.event_code.include?("curl")
    assert sdk.conversion_code.include?("curl")
  end

  test "platform SDKs have nil code snippets" do
    sdk = SdkRegistry.find(:shopify)

    assert_nil sdk.init_code
    assert_nil sdk.event_code
  end
end
