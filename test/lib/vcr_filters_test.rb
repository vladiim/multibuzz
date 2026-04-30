# frozen_string_literal: true

require "test_helper"
require "vcr_filters"

class VcrFiltersTest < ActiveSupport::TestCase
  test "redacts access_token query param" do
    assert_equal "https://graph.facebook.com/v19.0/me?access_token=<META_ACCESS_TOKEN>",
      VcrFilters.scrub("https://graph.facebook.com/v19.0/me?access_token=EAAReal123Token456")
  end

  test "redacts appsecret_proof query param" do
    assert_equal "https://graph.facebook.com/v19.0/me?appsecret_proof=<APPSECRET_PROOF>",
      VcrFilters.scrub("https://graph.facebook.com/v19.0/me?appsecret_proof=abcdef0123456789abcdef0123456789")
  end

  test "redacts fb_exchange_token in token-refresh URLs" do
    input = "https://graph.facebook.com/v19.0/oauth/access_token?grant_type=fb_exchange_token&fb_exchange_token=EAAlongLivedToken"

    assert_includes VcrFilters.scrub(input), "fb_exchange_token=<FB_EXCHANGE_TOKEN>"
  end

  test "redacts client_secret in OAuth bodies" do
    input = "client_id=123&client_secret=longsecretvaluehere&redirect_uri=https://x"

    assert_includes VcrFilters.scrub(input), "client_secret=<META_APP_SECRET>"
  end

  test "redacts OAuth code only when prefixed by ? or &" do
    input = "https://graph.facebook.com/oauth?code=AQDrealcodevalue123&redirect_uri=https://x"

    assert_includes VcrFilters.scrub(input), "code=<OAUTH_CODE>"
  end

  test "does not eat the word 'code' inside larger identifiers" do
    input = "https://graph.facebook.com/some_code_field/info"

    refute_includes VcrFilters.scrub(input), "<OAUTH_CODE>"
  end

  test "redacts access_token JSON value in response body" do
    body = '{"access_token":"EAATotallyRealToken123","token_type":"bearer","expires_in":5184000}'

    scrubbed = VcrFilters.scrub(body)

    assert_includes scrubbed, '"access_token":"<META_ACCESS_TOKEN>"'
    refute_includes scrubbed, "EAATotallyRealToken123"
  end

  test "redacts real-looking ad account IDs" do
    assert_equal "act_TEST_REDACTED", VcrFilters.scrub("act_1380769268857841")
  end

  test "preserves test placeholders that don't match the digit regex" do
    assert_equal "act_TEST_001", VcrFilters.scrub("act_TEST_001")
    assert_equal "act_FAKE_NOT_REDACTED", VcrFilters.scrub("act_FAKE_NOT_REDACTED")
  end

  test "is a no-op on nil and empty string" do
    assert_nil VcrFilters.scrub(nil)
    assert_equal "", VcrFilters.scrub("")
  end

  test "stacks multiple substitutions in one pass" do
    input = "POST /v19.0/oauth/access_token?client_id=123&client_secret=mysecretvalue&fb_exchange_token=EAAtoken123"

    scrubbed = VcrFilters.scrub(input)

    assert_includes scrubbed, "client_secret=<META_APP_SECRET>"
    assert_includes scrubbed, "fb_exchange_token=<FB_EXCHANGE_TOKEN>"
  end
end
