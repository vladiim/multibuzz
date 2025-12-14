require "test_helper"

class SdkHelperTest < ActionView::TestCase
  test "live_sdks returns live SDKs" do
    sdks = live_sdks

    assert sdks.any?
    assert sdks.all?(&:live?)
  end

  test "coming_soon_sdks returns coming_soon SDKs" do
    sdks = coming_soon_sdks

    assert sdks.any?
    assert sdks.all?(&:coming_soon?)
  end

  test "server_side_sdks returns server_side SDKs" do
    sdks = server_side_sdks

    assert sdks.any?
    assert sdks.all?(&:server_side?)
  end

  test "platform_sdks returns platform SDKs" do
    sdks = platform_sdks

    assert sdks.any?
    assert sdks.all?(&:platform?)
  end

  test "sdk_by_key returns SDK by key" do
    sdk = sdk_by_key(:ruby)

    assert_equal "Ruby", sdk.name
  end

  test "sdk_status_badge_class returns appropriate classes" do
    assert_equal "bg-green-100 text-green-800", sdk_status_badge_class(SdkStatuses::LIVE)
    assert_equal "bg-yellow-100 text-yellow-800", sdk_status_badge_class(SdkStatuses::BETA)
    assert_equal "bg-gray-100 text-gray-600", sdk_status_badge_class(SdkStatuses::COMING_SOON)
  end

  test "sdk_icon_path returns correct path" do
    sdk = sdk_by_key(:ruby)

    assert_equal "icons/sdks/ruby.svg", sdk_icon_path(sdk)
  end
end
