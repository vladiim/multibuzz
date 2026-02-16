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
    assert_equal "Ruby / Rails / Rack", sdk.display_name
  end

  test ".find returns nil for unknown key" do
    assert_nil SdkRegistry.find(:unknown)
  end

  test ".live returns only live SDKs" do
    sdks = SdkRegistry.live

    assert sdks.any?
    assert sdks.all?(&:live?)
  end

  test ".coming_soon returns empty when no coming_soon SDKs exist" do
    sdks = SdkRegistry.coming_soon

    assert_empty sdks
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

  test ".for_onboarding returns all SDKs" do
    sdks = SdkRegistry.for_onboarding

    assert_equal SdkRegistry.all.count, sdks.count
  end

  test ".for_homepage returns all SDKs" do
    sdks = SdkRegistry.for_homepage

    assert_equal SdkRegistry.all.count, sdks.count
  end

  # Sdk struct tests
  test "Sdk#live? returns true for live status" do
    sdk = SdkRegistry.find(:ruby)

    assert sdk.live?
    assert_not sdk.coming_soon?
    assert_not sdk.beta?
  end

  test "Sdk#coming_soon? returns true for coming_soon status" do
    sdk = build_sdk(status: SdkStatuses::COMING_SOON)

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
    live_sdk = SdkRegistry.live.first
    coming_soon_sdk = build_sdk(status: SdkStatuses::COMING_SOON)

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

  # Tag manager tests
  test ".tag_manager returns only tag_manager SDKs" do
    sdks = SdkRegistry.tag_manager

    assert sdks.any?
    assert sdks.all?(&:tag_manager?)
  end

  test "Sdk#tag_manager? returns true for tag_manager category" do
    sdk = SdkRegistry.find(:sgtm)

    assert sdk.tag_manager?
    assert_not sdk.server_side?
    assert_not sdk.platform?
    assert_not sdk.api?
  end

  test ".find returns sGTM SDK by key" do
    sdk = SdkRegistry.find(:sgtm)

    assert_equal "sgtm", sdk.key
    assert_equal "Google Tag Manager", sdk.name
    assert_equal "Server-Side GTM", sdk.display_name
    assert_equal "tag_manager", sdk.category
  end

  test "sGTM has nil code snippets" do
    sdk = SdkRegistry.find(:sgtm)

    assert_nil sdk.init_code
    assert_nil sdk.event_code
    assert_nil sdk.conversion_code
  end

  # custom_install? tests
  test "Sdk#custom_install? returns true for platform SDKs" do
    assert SdkRegistry.find(:shopify).custom_install?
  end

  test "Sdk#custom_install? returns true for tag_manager SDKs" do
    assert SdkRegistry.find(:sgtm).custom_install?
  end

  test "Sdk#custom_install? returns false for server_side SDKs" do
    assert_not SdkRegistry.find(:ruby).custom_install?
  end

  test "Sdk#custom_install? returns false for api SDKs" do
    assert_not SdkRegistry.find(:rest_api).custom_install?
  end

  private

  def build_sdk(status:, category: SdkCategories::SERVER_SIDE)
    SdkRegistry::Sdk.new(
      key: "test", name: "Test", display_name: "Test SDK", icon: "test",
      package_name: nil, package_manager: nil, package_url: nil,
      github_url: nil, docs_url: nil, status: status, released_at: nil,
      category: category, sort_order: 99, install_command: nil,
      init_code: nil, event_code: nil, conversion_code: nil,
      identify_code: nil, middleware_code: nil, verification_command: nil
    )
  end
end
