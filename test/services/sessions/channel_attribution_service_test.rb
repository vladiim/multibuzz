require "test_helper"

class Sessions::ChannelAttributionServiceTest < ActiveSupport::TestCase
  test "returns paid_search for utm_medium=cpc" do
    utm_data = { utm_medium: "cpc", utm_source: "google" }

    assert_equal Channels::PAID_SEARCH, service(utm_data).call
  end

  test "returns paid_search for utm_medium=ppc" do
    utm_data = { utm_medium: "ppc" }

    assert_equal Channels::PAID_SEARCH, service(utm_data).call
  end

  test "returns email for utm_medium=email" do
    utm_data = { utm_medium: "email" }

    assert_equal Channels::EMAIL, service(utm_data).call
  end

  test "returns display for utm_medium=display" do
    utm_data = { utm_medium: "display" }

    assert_equal Channels::DISPLAY, service(utm_data).call
  end

  test "returns paid_social for utm_medium=social with social source" do
    utm_data = { utm_medium: "social", utm_source: "facebook" }

    assert_equal Channels::PAID_SOCIAL, service(utm_data).call
  end

  test "returns organic_social for utm_medium=social without social source" do
    utm_data = { utm_medium: "social", utm_source: "newsletter" }

    assert_equal Channels::ORGANIC_SOCIAL, service(utm_data).call
  end

  test "returns organic_search from google.com referrer" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://google.com/search").call
  end

  test "returns organic_search from bing.com referrer" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://www.bing.com/search").call
  end

  test "returns organic_social from facebook.com referrer" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "https://facebook.com/post/123").call
  end

  test "returns organic_social from linkedin.com referrer" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "https://www.linkedin.com/feed").call
  end

  test "returns video from youtube.com referrer" do
    assert_equal Channels::VIDEO, service({}, "https://youtube.com/watch").call
  end

  test "returns referral from unknown domain referrer" do
    assert_equal Channels::REFERRAL, service({}, "https://example.com/blog").call
  end

  test "returns direct when no utm and no referrer" do
    assert_equal Channels::DIRECT, service({}, nil).call
  end

  test "returns direct when empty utm and empty referrer" do
    assert_equal Channels::DIRECT, service({}, "").call
  end

  test "prefers utm over referrer" do
    utm_data = { utm_medium: "email" }

    assert_equal Channels::EMAIL, service(utm_data, "https://google.com").call
  end

  test "handles string keys in utm_data" do
    utm_data = { "utm_medium" => "cpc", "utm_source" => "google" }

    assert_equal Channels::PAID_SEARCH, service(utm_data).call
  end

  test "returns other for unrecognized utm_medium" do
    utm_data = { utm_medium: "unknown_medium" }

    assert_equal Channels::OTHER, service(utm_data).call
  end

  test "handles invalid referrer URL gracefully" do
    assert_equal Channels::DIRECT, service({}, "not a valid url").call
  end

  private

  def service(utm_data = {}, referrer = nil)
    Sessions::ChannelAttributionService.new(utm_data, referrer)
  end
end
