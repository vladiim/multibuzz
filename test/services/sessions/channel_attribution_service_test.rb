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

  test "returns other for unrecognized utm_medium without referrer" do
    utm_data = { utm_medium: "unknown_medium" }

    assert_equal Channels::OTHER, service(utm_data).call
  end

  test "falls back to referrer when utm_medium is unrecognized" do
    utm_data = { utm_medium: "unknown_medium" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data, "https://google.com/search").call
  end

  test "returns organic_search when utm_source is google without utm_medium" do
    utm_data = { utm_source: "google" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data).call
  end

  test "utm_source takes priority over referrer" do
    # utm_source says google (search), but referrer is facebook (social)
    # utm_source should win since UTM has priority over referrer
    utm_data = { utm_source: "google" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data, "https://facebook.com/post").call
  end

  test "utm_source priority over referrer with different channels" do
    # utm_source says youtube (video), but referrer is linkedin (social)
    utm_data = { utm_source: "youtube" }

    assert_equal Channels::VIDEO, service(utm_data, "https://linkedin.com/feed").call
  end

  test "returns organic_social when utm_source is facebook without utm_medium" do
    utm_data = { utm_source: "facebook" }

    assert_equal Channels::ORGANIC_SOCIAL, service(utm_data).call
  end

  test "returns video when utm_source is youtube without utm_medium" do
    utm_data = { utm_source: "youtube" }

    assert_equal Channels::VIDEO, service(utm_data).call
  end

  test "returns other when utm_source is unrecognized without utm_medium" do
    utm_data = { utm_source: "newsletter" }

    assert_equal Channels::OTHER, service(utm_data).call
  end

  test "handles invalid referrer URL gracefully" do
    assert_equal Channels::DIRECT, service({}, "not a valid url").call
  end

  # ==========================================
  # Database lookup integration tests
  # ==========================================

  test "uses database lookup for known referrer" do
    ReferrerSource.create!(
      domain: "duckduckgo.com",
      source_name: "DuckDuckGo",
      medium: ReferrerSources::Mediums::SEARCH,
      keyword_param: "q",
      data_origin: ReferrerSources::DataOrigins::MATOMO_SEARCH
    )

    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://duckduckgo.com/search").call
  end

  test "returns other for spam referrer from database" do
    ReferrerSource.create!(
      domain: "spam-referrer.com",
      source_name: "spam-referrer.com",
      medium: ReferrerSources::Mediums::SOCIAL,
      is_spam: true,
      data_origin: ReferrerSources::DataOrigins::MATOMO_SPAM
    )

    assert_equal Channels::OTHER, service({}, "https://spam-referrer.com/evil").call
  end

  test "falls back to patterns when not in database" do
    # google.com not in database, but matches SEARCH_ENGINES pattern
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://google.com/search").call
  end

  private

  def service(utm_data = {}, referrer = nil)
    Sessions::ChannelAttributionService.new(utm_data, referrer)
  end
end
