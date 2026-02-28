# frozen_string_literal: true

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
  # Paid Social Detection Tests
  # ==========================================

  test "returns paid_social for utm_medium=paid_social" do
    utm_data = { utm_medium: "paid_social", utm_source: "facebook" }

    assert_equal Channels::PAID_SOCIAL, service(utm_data).call
  end

  test "returns paid_social for utm_medium=paid with social source" do
    utm_data = { utm_medium: "paid", utm_source: "facebook" }

    assert_equal Channels::PAID_SOCIAL, service(utm_data).call
  end

  test "returns paid_search for utm_medium=paid with non-social source" do
    utm_data = { utm_medium: "paid", utm_source: "google" }

    assert_equal Channels::PAID_SEARCH, service(utm_data).call
  end

  # ==========================================
  # Click ID Attribution Tests
  # ==========================================

  test "returns paid_search for gclid presence" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { gclid: "abc123" }).call
  end

  test "returns paid_social for fbclid presence" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { fbclid: "abc123" }).call
  end

  test "returns display for dclid presence" do
    assert_equal Channels::DISPLAY, service({}, nil, { dclid: "abc123" }).call
  end

  test "click_id takes priority over referrer" do
    # gclid says paid_search, referrer says social
    assert_equal Channels::PAID_SEARCH, service({}, "https://facebook.com", { gclid: "abc" }).call
  end

  test "click_id takes priority over utm (GA4 alignment)" do
    # click_id is most reliable signal for paid traffic
    # gclid says paid_search, utm says email - trust the click_id
    utm_data = { utm_medium: "email" }

    assert_equal Channels::PAID_SEARCH, service(utm_data, nil, { gclid: "abc" }).call
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

  # ==========================================
  # Google Places (plcid) Detection Tests
  # ==========================================

  test "returns organic_search for plcid in utm_term" do
    utm_data = { utm_term: "plcid_8067905893793481977" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data).call
  end

  test "returns organic_search for plcid with google referrer" do
    utm_data = { utm_term: "plcid_123456789" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data, "https://www.google.com/").call
  end

  test "returns organic_search for plcid with path suffix" do
    # Real-world patterns from Google Business Profile
    utm_data = { utm_term: "plcid_788967457395580423/contact" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data).call
  end

  test "returns organic_search for plcid with various path suffixes" do
    suffixes = [ "/contact-us", "/about", "/info", "/contact.html", "/contact.php" ]

    suffixes.each do |suffix|
      utm_data = { utm_term: "plcid_123456789#{suffix}" }

      assert_equal Channels::ORGANIC_SEARCH, service(utm_data).call,
        "Expected organic_search for plcid with suffix #{suffix}"
    end
  end

  test "plcid takes priority over utm_medium (GA4 alignment)" do
    # plcid is a Google Places click identifier - most reliable signal
    # Even with utm_medium set, plcid indicates Google Maps/Business traffic
    utm_data = { utm_medium: "email", utm_term: "plcid_123456789" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data).call
  end

  test "plcid takes priority over referrer" do
    # plcid indicates Google Places, even if referrer is something else
    utm_data = { utm_term: "plcid_123456789" }

    assert_equal Channels::ORGANIC_SEARCH, service(utm_data, "https://example.com/").call
  end

  test "non-plcid utm_term does not trigger organic_search" do
    # Regular utm_term keywords should not be treated as plcid
    utm_data = { utm_term: "dog boarding melbourne" }

    assert_equal Channels::DIRECT, service(utm_data).call
  end

  # ==========================================
  # Comprehensive Click ID → Channel Tests
  # ==========================================

  # Google Ecosystem
  test "returns paid_search for gclid" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { gclid: "abc123" }).call
  end

  test "returns paid_search for gbraid (iOS app)" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { gbraid: "abc123" }).call
  end

  test "returns paid_search for wbraid (web-to-app)" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { wbraid: "abc123" }).call
  end

  test "returns paid_search for gclsrc" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { gclsrc: "aw.ds" }).call
  end

  # Microsoft
  test "returns paid_search for msclkid" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { msclkid: "abc123" }).call
  end

  # Meta (Facebook/Instagram)
  test "returns paid_social for fbclid" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { fbclid: "abc123" }).call
  end

  # TikTok
  test "returns paid_social for ttclid" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { ttclid: "abc123" }).call
  end

  # LinkedIn
  test "returns paid_social for li_fat_id" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { li_fat_id: "abc123" }).call
  end

  # Twitter/X
  test "returns paid_social for twclid" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { twclid: "abc123" }).call
  end

  # Pinterest
  test "returns paid_social for epik" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { epik: "abc123" }).call
  end

  # Snapchat
  test "returns paid_social for sclid (snapchat lowercase)" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { sclid: "abc123" }).call
  end

  test "returns paid_social for ScCid (snapchat mixed case)" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { ScCid: "abc123" }).call
  end

  # Reddit
  test "returns paid_social for rdt_cid" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { rdt_cid: "abc123" }).call
  end

  # Quora
  test "returns paid_social for qclid" do
    assert_equal Channels::PAID_SOCIAL, service({}, nil, { qclid: "abc123" }).call
  end

  # Yahoo
  test "returns paid_search for vmcid (yahoo)" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { vmcid: "abc123" }).call
  end

  # Yandex
  test "returns paid_search for yclid (yandex)" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { yclid: "abc123" }).call
  end

  # Seznam (Czech)
  test "returns paid_search for sznclid (seznam)" do
    assert_equal Channels::PAID_SEARCH, service({}, nil, { sznclid: "abc123" }).call
  end

  # ==========================================
  # Referrer URL Normalization Tests
  # ==========================================

  test "handles referrer without protocol" do
    # Some referrers may be stored without https://
    assert_equal Channels::ORGANIC_SEARCH, service({}, "www.google.com").call
  end

  test "handles referrer without protocol or www" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "google.com").call
  end

  test "handles referrer with just domain for social" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "facebook.com").call
  end

  # ==========================================
  # Internal Referrer Detection Tests
  # Same-host referrers should be treated as direct
  # ==========================================

  test "returns direct when referrer host matches page host" do
    result = service({}, "https://example.com/page1", {}, page_host: "example.com").call

    assert_equal Channels::DIRECT, result
  end

  test "returns direct when referrer host matches page host with www" do
    result = service({}, "https://www.example.com/page1", {}, page_host: "example.com").call

    assert_equal Channels::DIRECT, result
  end

  test "returns direct when page host has www and referrer does not" do
    result = service({}, "https://example.com/page1", {}, page_host: "www.example.com").call

    assert_equal Channels::DIRECT, result
  end

  test "returns referral when referrer host differs from page host" do
    result = service({}, "https://other-site.com/page", {}, page_host: "example.com").call

    assert_equal Channels::REFERRAL, result
  end

  test "returns organic_search when referrer is google even with page_host" do
    result = service({}, "https://google.com/search", {}, page_host: "example.com").call

    assert_equal Channels::ORGANIC_SEARCH, result
  end

  test "utm takes priority over internal referrer detection" do
    utm_data = { utm_medium: "email" }
    result = service(utm_data, "https://example.com/page", {}, page_host: "example.com").call

    assert_equal Channels::EMAIL, result
  end

  test "internal referrer detection handles port numbers in referrer" do
    result = service({}, "https://example.com:443/page", {}, page_host: "example.com").call

    assert_equal Channels::DIRECT, result
  end

  test "internal referrer detection is case insensitive" do
    result = service({}, "https://EXAMPLE.COM/page", {}, page_host: "example.com").call

    assert_equal Channels::DIRECT, result
  end

  test "internal referrer detection handles nil page_host gracefully" do
    result = service({}, "https://example.com/page", {}, page_host: nil).call

    assert_equal Channels::REFERRAL, result
  end

  test "internal referrer detection handles subdomains correctly" do
    # subdomain.example.com referring to example.com should be referral (different hosts)
    result = service({}, "https://blog.example.com/post", {}, page_host: "example.com").call

    assert_equal Channels::REFERRAL, result
  end

  # ==========================================
  # AI Channel Attribution Tests
  # ==========================================

  test "returns ai for chatgpt.com referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://chatgpt.com/").call
  end

  test "returns ai for perplexity.ai referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://perplexity.ai/search").call
  end

  test "returns ai for claude.ai referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://claude.ai/chat").call
  end

  test "returns ai for gemini.google.com referrer via regex fallback" do
    # Must match AI_ENGINES before SEARCH_ENGINES catches "google"
    assert_equal Channels::AI, service({}, "https://gemini.google.com/app").call
  end

  test "returns ai for copilot.microsoft.com referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://copilot.microsoft.com/").call
  end

  test "returns ai for meta.ai referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://meta.ai/").call
  end

  test "returns ai for chat.openai.com referrer via regex fallback" do
    assert_equal Channels::AI, service({}, "https://chat.openai.com/chat").call
  end

  test "returns ai for utm_medium=ai" do
    utm_data = { utm_medium: "ai" }

    assert_equal Channels::AI, service(utm_data).call
  end

  test "returns ai for utm_source=chatgpt without utm_medium" do
    utm_data = { utm_source: "chatgpt" }

    assert_equal Channels::AI, service(utm_data).call
  end

  test "returns ai for utm_source=perplexity without utm_medium" do
    utm_data = { utm_source: "perplexity" }

    assert_equal Channels::AI, service(utm_data).call
  end

  test "utm_medium overrides ai referrer" do
    # Explicit UTM tagging takes priority over referrer
    utm_data = { utm_medium: "cpc", utm_source: "google" }

    assert_equal Channels::PAID_SEARCH, service(utm_data, "https://chatgpt.com/").call
  end

  test "click_id overrides ai referrer" do
    assert_equal Channels::PAID_SOCIAL, service({}, "https://chatgpt.com/", { fbclid: "abc123" }).call
  end

  test "returns ai from database lookup with ai medium" do
    ReferrerSource.create!(
      domain: "chatgpt.com",
      source_name: "ChatGPT",
      medium: ReferrerSources::Mediums::AI,
      data_origin: ReferrerSources::DataOrigins::CUSTOM
    )

    assert_equal Channels::AI, service({}, "https://chatgpt.com/share/abc").call
  end

  test "gemini.google.com database lookup returns ai not organic_search" do
    ReferrerSource.create!(
      domain: "gemini.google.com",
      source_name: "Gemini",
      medium: ReferrerSources::Mediums::AI,
      data_origin: ReferrerSources::DataOrigins::CUSTOM
    )

    assert_equal Channels::AI, service({}, "https://gemini.google.com/app").call
  end

  test "regular google.com still returns organic_search" do
    # Ensure AI additions don't break existing google classification
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://www.google.com/search?q=test").call
  end

  test "regular bing.com still returns organic_search" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://www.bing.com/search").call
  end

  # Self-referral detection

  test "returns direct when referrer is from account's own domain" do
    own_domains = %w[northshore.pettechpro.com.au petresortsaustralia.com.au]

    result = service(
      {},
      "https://northshore.pettechpro.com.au/search",
      {},
      page_host: "petresortsaustralia.com.au",
      account_domains: own_domains
    ).call

    assert_equal Channels::DIRECT, result
  end

  test "returns referral when referrer is not in account domains" do
    own_domains = %w[petresortsaustralia.com.au]

    result = service(
      {},
      "https://binance.com",
      {},
      page_host: "petresortsaustralia.com.au",
      account_domains: own_domains
    ).call

    assert_equal Channels::REFERRAL, result
  end

  test "self-referral detection is case insensitive and strips www" do
    own_domains = %w[pettechpro.com.au]

    result = service(
      {},
      "https://www.PetTechPro.com.au/booking",
      {},
      page_host: "other-site.com.au",
      account_domains: own_domains
    ).call

    assert_equal Channels::DIRECT, result
  end

  test "utm parameters take priority over self-referral detection" do
    own_domains = %w[northshore.pettechpro.com.au]

    result = service(
      { utm_medium: "cpc", utm_source: "google" },
      "https://northshore.pettechpro.com.au/search",
      {},
      page_host: "petresortsaustralia.com.au",
      account_domains: own_domains
    ).call

    assert_equal Channels::PAID_SEARCH, result
  end

  # ==========================================
  # Additional Search Engine Tests
  # ==========================================

  test "returns organic_search from search.brave.com referrer" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://search.brave.com/search?q=dog+boarding").call
  end

  test "returns organic_search from syndicatedsearch.goog referrer" do
    assert_equal Channels::ORGANIC_SEARCH, service({}, "https://syndicatedsearch.goog/").call
  end

  # ==========================================
  # Additional Social Network Tests
  # ==========================================

  test "returns organic_social from t.co referrer" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "https://t.co/abc123").call
  end

  test "returns organic_social from threads.com referrer" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "https://www.threads.com/").call
  end

  test "returns organic_social from threads.net referrer" do
    assert_equal Channels::ORGANIC_SOCIAL, service({}, "https://www.threads.net/@user").call
  end

  test "t.co pattern does not false-match att.com" do
    assert_equal Channels::REFERRAL, service({}, "https://att.com/wireless").call
  end

  # ==========================================
  # Webmail / Email Provider Referrer Tests
  # ==========================================

  test "returns email from webmail referrer" do
    assert_equal Channels::EMAIL, service({}, "https://webmail.optusnet.com.au/").call
  end

  test "returns email from webmail subdomain on any domain" do
    assert_equal Channels::EMAIL, service({}, "https://webmail.bigpond.com/mail").call
  end

  private

  def service(utm_data = {}, referrer = nil, click_ids = {}, page_host: nil, account_domains: [])
    Sessions::ChannelAttributionService.new(utm_data, referrer, click_ids, page_host: page_host, account_domains: account_domains)
  end
end
